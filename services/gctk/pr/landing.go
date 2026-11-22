package pr

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"math/rand/v2"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The landing order and the publication it reads (specs/tk-1tfzr71.66/design.md,
// sections 4 and 6, and specs/tk-1tfzr71.149/design.md, section 5). The
// refinery publishes a PR's pending record with Record, and the landing order's
// runs act on each record with Reconcile. The order is the second of the PR's
// two loops. The PR watch (refresh.go) keeps the read saved on each PR's bead
// current, and a run finds and does its work from that saved read and the
// store alone, so no run reads GitHub to learn whether a record has work. The
// store holds what the city did: the head the refinery validated, the merge a
// run verified, the exceptions a run recorded and the waits on the bead. The
// saved read holds what GitHub showed when the watch last read it. A run
// decides every record from one pass of the store, and takes the record lock
// only for a record that owes an act, which it decides again under the lock
// before it acts.
//
// Only the merge checks GitHub before it acts, since a merge made in error puts
// work on the target, which no run takes back, and GitHub's rules refuse what
// else could go wrong with it: a run has the one-PR update re-read the PR in
// full with the lock free
// (Reread), decides again on what that read saved, and requests the merge
// pinned to the head it judged. Every other act reads of GitHub only what it
// changes. A withdrawal reads the reviews it dismisses and their threads, a
// send-back and a landing fetch the branch they judge, and a label write leaves
// the PR's labels to their writer, which reads them itself. A run requests a
// merge, closes a bead once the merge commit is on the target, hands a changed
// head to the refinery and sees that the refinery hears of it, keeps the
// exceptions blocked behind a human gate, marks a draft ready and carries out
// an approval's withdrawal. A bead's assignee says who works it now (Gas City's
// delivery of work to a session): the refinery while it validates a head, and
// nobody while the PR waits. A run works a bead assigned to nobody or to the
// refinery, and leaves one assigned to anyone else to that assignee. A ruling
// that retires a PR records its disposition on the bead under the record lock
// and then closes the PR (pr-dispose.sh). A run requests no merge of a PR whose
// bead carries it, and once the saved read shows the PR closed the bead goes to
// the disposition writer, bead-rehome.sh, which closes it onto the successor the
// ruling named, with the lock free, while the bead still has the status and
// assignee the run judged and still records that ruling. A run saves none of
// what GitHub says: the one-PR update is the one writer of GitHub's side on a
// bead, the saved read, pr_state and pr_last_checked_at. Both take the store's
// record lock, Record across both of its writes and a run for one act at a
// time, and every write they make carries bd's guards on the status and the
// assignee read under the lock, so neither writes over a bead that a close or
// an assignment reached first. A run that lands a PR on the rig's default
// branch then checks that branch's seed audit with the lock free, and asks for
// the branch's re-render when the audit is stale, holding no PR for it (the
// design's call 1).

// Hub is GitHub as the landing order and the draft cycle reach it: the reads an
// act makes of what it changes, such as a withdrawal's of the reviews it
// dismisses, a merge request or an enqueue pinned to the head the evaluator
// judged, the PR's moves between draft and ready, the dismissal of a review,
// and the reaction the take leaves on a post, named by its node id.
type Hub interface {
	GitHub
	MergePullRequest(id, head string) error
	EnqueuePullRequest(id, head string) error
	MarkReady(id string) error
	ConvertToDraft(id string) error
	DismissReview(repo string, number int, id int64, message string) error
	AddReaction(subject, content string) error
}

// Checkout is the rig's clone, as the record reads it: its origin, the target
// it fetches, stopped when ctx ends, whether a merge commit is on the target
// fetched, whether one commit contains another in the history it holds, its
// default branch, and a branch's tip as it was last fetched.
type Checkout interface {
	OriginURL() (string, error)
	FetchBranch(ctx context.Context, branch string) error
	Reaches(commit, branch string) (bool, error)
	Contains(commit, ancestor string) (bool, error)
	DefaultBranch() (string, error)
	Tip(branch string) (string, error)
}

// Audit is the seed audit a landing can leave stale: the pages a repository
// renders from its whole tree and commits per branch, so a landing whose render
// was made before another landing moved an input, or a gc that moved the text
// its own packs carry, leaves the default branch committing pages that no longer
// render as committed. Stale names those pages at a commit, and Reaudit hands
// them to the one writer of the default branch's re-render.
type Audit interface {
	// Stale names each page of the audit that commit commits other than as its
	// tree renders it, none when every page renders as committed. An error is a
	// check that did not run.
	Stale(commit string) ([]string, error)
	// Reaudit hands the pages branch is stale in to the writer of its
	// re-render, with who found them, and returns what the writer answered.
	Reaudit(branch, seenBy string, pages []string) (string, error)
}

// Gates files a human gate on a bead under a key, or finds the one open there,
// stopped once ctx ends.
type Gates interface {
	File(ctx context.Context, subject, key, message string) error
}

// Waker wakes a session and nudges it with a message, so a session that is
// asleep starts and one that is up gets a turn, as a polecat's hand-off to the
// refinery does (work-submit.sh), stopped once ctx ends. An error says which
// of the two did not land.
type Waker interface {
	Wake(ctx context.Context, session, message string) error
}

// Dispositions is the writer of a close that is not a landing, bead-rehome.sh,
// as the landing order reaches it for a bead whose PR a ruling retired. Close
// closes the bead x names onto the successor its ruling named, under its kind,
// with its note beside the close, acting as the refinery. The writer takes the
// store's record lock itself, from its read of the bead to its close, so the
// order calls it with the lock free, and it closes the bead only while the bead
// still has the status and assignee the run judged it under and still records
// the ruling the run read. A close the writer
// holds for now, because a wait on the bead is still open or the bead moved
// since the run judged it or since the writer read it, is a *HeldClose. An act
// does not stop the writer, since it ends the bead's branch on the git remote
// once the close has landed, and a stop between the two would leave the branch
// of a closed bead, which no run of the order reads again.
type Dispositions interface {
	Close(x Disposal) error
}

// Disposal is the close a run owes a bead whose PR closed under a ruling's
// disposition, which it hands to the disposition writer once the record lock
// is free: the bead, the status and assignee the run judged it under with the
// lock held, the disposition it read there, and the note the close carries.
type Disposal struct {
	Bead, Status, Assignee, Note string
	Disposition                  Disposition
}

// Disposition is the close a ruling recorded on the bead that owns a PR before
// it closed the PR (pr-dispose.sh): its kind, the bead that carries the work
// now or, under not-needed, the evidence that ruled the work out, and that
// bead's store when its id prefix alone does not place it.
type Disposition struct {
	Kind, Successor, Store string
}

// ruling says what the ruling recorded, for a run's outcome.
func (d Disposition) ruling() string {
	return fmt.Sprintf("a ruling recorded its disposition, %s onto %s", d.Kind, d.Successor)
}

// HeldClose is a disposition's close the writer holds for now, saying why: a
// wait still open on the bead, such as the conversation of the sitting that
// ruled, or a move since the run judged the bead or the writer read it, such as
// an assignment or a second ruling. The next run reads the bead again.
type HeldClose struct{ Why string }

func (e *HeldClose) Error() string { return e.Why }

// Landing is what the record's verbs act through. Dir is the store's .beads
// directory, where the record lock lives, and Refinery the refinery's assignee,
// the one a hand-over of a changed head assigns, which is also the session Wake
// wakes. Hub is GitHub on a host, each call stopped when ctx ends. Reread is
// the one-PR update's read of every part of the PR at url (Watcher.Reread),
// which a run has make before it requests a merge, stopped once ctx ends, and
// a run requests no merge when it is nil. RefreshConversation is the one-PR
// update's read of the conversation of the PR at url
// (Watcher.RefreshConversation), which a take has make once its marks have
// landed, stopped once ctx ends. Feedback loads the definition of
// feedback, once a withdrawal first needs it. Mark reads the
// city's mark, which a dismissal's message carries, from the writer that owns
// it. Runs pours a PR's review run, and Dispositions closes a bead whose PR a
// ruling retired. Audit is the rig's seed audit, nil for a rig whose repository
// carries none. Wake gives the refinery a turn for a changed head that only
// conversations and asks hold. Labels keeps the labels of each PR the store's
// live beads own equal to the ones the store derives, and a run writes none
// when it is nil. Wait bounds how long a writer waits for the lock, and Yield
// is how long a run lets the lock stand free between two acts, so a writer
// waiting for it takes it. Shuffle orders the acts a run takes, at random when
// nil. Now is the clock a write's stamp and a run's window read, the system's
// when nil.
type Landing struct {
	Ledger   *ledger.Ledger
	Dir      string
	Refinery string
	Hub      func(ctx context.Context, host string) Hub
	Reread   func(ctx context.Context, url string) error
	// RefreshConversation is described above, with Reread.
	RefreshConversation func(ctx context.Context, url string) error
	Feedback            func() (Feedback, error)
	Mark                func() (string, error)
	Checkout            Checkout
	Gates               Gates
	Runs                Runs
	Dispositions        Dispositions
	Audit               Audit
	Wake                Waker
	Labels              Labels
	Now                 func() time.Time
	Wait                time.Duration
	Yield               time.Duration
	Shuffle             func([]string)
}

// stamp is the time a write records, RFC 3339 UTC to the second, the form whose
// order is its text's order.
func (l Landing) stamp() string { return stamp(l.Now) }

// Refusal is a publication the bead's state refused: it was closed, or not the
// refinery's, when the publication read it, or it moved between that read and a
// write, which bd's guard refused. Armed says whether the first write, the
// marker, had landed.
type Refusal struct {
	Bead, Why string
	Armed     bool
}

func (e *Refusal) Error() string {
	if e.Armed {
		return fmt.Sprintf("%s: the marker landed and the record did not: %s", e.Bead, e.Why)
	}
	return fmt.Sprintf("%s: nothing written: %s", e.Bead, e.Why)
}

// Record writes the pending record of p on bead, in Gas Town's two writes,
// holding the record lock across both: first the marker and the PR the refinery
// may reuse, then the whole record with the bead blocked and assigned to
// nobody. It reads the bead under the lock first, and writes only on a bead that
// is not closed and is assigned to the refinery, each write guarded on the
// status and assignee it read. A bead it refuses returns a *Refusal. The PR
// must be in the rig's own repository, which Record checks before it takes the
// lock.
func (l Landing) Record(bead string, p record.Publication) error {
	if err := p.Valid(); err != nil {
		return err
	}
	host, _, _, _ := record.ParseURL(p.URL)
	if err := l.sameOrigin(host, p.Repo); err != nil {
		return err
	}
	release, err := record.Lock(l.Dir, l.Wait)
	if err != nil {
		return err
	}
	defer release()
	r, err := l.read(bead)
	if err != nil {
		return err
	}
	if r == nil {
		return fmt.Errorf("%s: the store holds no such bead", bead)
	}
	status, assignee := r.Status(), r.Assignee()
	switch {
	case status == "closed":
		return &Refusal{Bead: bead, Why: "it is closed"}
	case assignee != l.Refinery:
		return &Refusal{Bead: bead, Why: fmt.Sprintf("it is assigned to %s, not to the refinery, %s", nobody(assignee), l.Refinery)}
	}
	arm := l.Ledger.Write(bead)
	arm.Guard(status, assignee)
	record.Arm(arm, p.URL)
	if err := l.Ledger.Commit(arm); err != nil {
		if errors.Is(err, ledger.ErrGuard) {
			return &Refusal{Bead: bead, Why: "it was closed or reassigned after this publication read it"}
		}
		return err
	}
	publish := l.Ledger.Write(bead)
	publish.Guard(status, assignee)
	record.Publish(publish, p)
	if err := l.Ledger.Commit(publish); err != nil {
		if errors.Is(err, ledger.ErrGuard) {
			return &Refusal{Bead: bead, Armed: true, Why: "it was closed or reassigned between the publication's two writes"}
		}
		return fmt.Errorf("%s: the marker landed and the record did not: %w", bead, err)
	}
	return nil
}

// RunOutcome is what a run did with one record: the bead, the action and why.
type RunOutcome struct {
	Bead, Action, Detail string
}

// The actions a run reports.
const (
	// ActChecked: the record owes no act, and the run wrote nothing on the bead:
	// the PR stands as the record says, the bead holds no saved read of the PR
	// current for it yet, which the PR watch's next pass saves, or the
	// disposition writer holds a retired PR's close for now, and the next run
	// hands it over again.
	ActChecked = "checked"
	// ActRequested: the evaluator found the PR ready on the saved read, the
	// one-PR update re-read the PR in full, the evaluator found it ready on what
	// that read saved, and the run asked GitHub to merge it, or to add it to its
	// base's merge queue, at the head it judged.
	ActRequested = "requested"
	// ActReadied: the PR was a draft whose record is pending at its head, a
	// passed review result names that head and its target, and no review run is
	// attached and no ask a run can take is open, so the run marked it ready for
	// review.
	ActReadied = "readied"
	// ActPoured: the PR is open at the head the refinery validated with no
	// passed review result there, or an ask a run can take is open, and nothing
	// else writes the branch, so the run poured a review run attached to the
	// bead.
	ActPoured = "poured"
	// ActLanded: the merge commit is on the target, and the bead closed.
	ActLanded = "landed"
	// ActDisposed: the PR closed under the disposition a ruling recorded, and
	// the disposition writer closed the bead onto the ruling's successor.
	ActDisposed = "disposed"
	// ActRequeued: the PR is open at another head, and the run recorded it,
	// handing the head to the refinery unless something the order owes holds it.
	ActRequeued = "requeued"
	// ActRevalidate: the record was half written, and the bead went back to the
	// refinery for its full validation.
	ActRevalidate = "revalidate"
	// ActExcepted: an exception, filed as a human gate, keeps the bead blocked.
	ActExcepted = "excepted"
	// ActRetry: the record's act did not complete, or the run could not decide
	// it: a call GitHub refused or did not answer, a merge's re-read that did
	// not save, a fetch, a read, a filing or a label write that failed, or an
	// act stopped at its bound. Nothing records it, the difference stays on the
	// bead, and the next run acts on it again.
	ActRetry = "retry"
	// ActLabeled: the status: and held: labels the one-PR update saved for the
	// PR differ from the ones the store derives, and the run had the labels'
	// writer, which reads the PR's labels itself, write them: the derived labels
	// on a PR the saved read shows open, and none on one it shows merged or
	// closed.
	ActLabeled = "labeled"
	// ActAssigned: the bead is assigned to someone other than the refinery, who
	// works it now, so the act wrote nothing to it, requested no merge and
	// poured no review run. A run decides no such bead in its pass (plan), so
	// this one was assigned after the pass read it, and a later run works it
	// once the assignee is gone.
	ActAssigned = "assigned"
	// ActSettled: no further run is owed, and the run cleared the marker.
	ActSettled = "settled"
	// ActTaken: the read saved on the bead held posts that are feedback the
	// city has not taken, and the run filed the ask of each, or found the one
	// filed before, marked each post with the city's EYES, and had the one-PR
	// update read the PR's conversation again.
	ActTaken = "taken"
	// ActBlocked: the publication's second write had landed on a bead still
	// open, and the run moved it to blocked.
	ActBlocked = "blocked"
	// ActMoved: the bead moved since the run read it under the lock, so bd's
	// guard refused the write and nothing landed. The next run reads it as it
	// stands.
	ActMoved = "moved"
	// ActSkipped: the bead no longer carries the marker, or its status is none
	// the record knows.
	ActSkipped = "skipped"
	// ActLeft: the run had used its window before it reached the record's act,
	// or the act had less of its bound left than a review run's pour reserves
	// (pourReserve), so the next run acts on it, or a take had less of its bound
	// left than the read that saves its marks reserves (refreshReserve), so the
	// next run takes the posts it left.
	ActLeft = "left"
	// ActFailed: a write or a read of the store failed in a way the next run may
	// not clear.
	ActFailed = "failed"
)

// Options bound one run: Window is how long into the run it starts another
// act, and Stop how long one act runs before it is stopped, with whatever
// GitHub call, fetch, store read or write, human gate's filing or refinery's
// wake it is making. A review run's pour is the one call in an act the stop
// does not end, since a cook stopped before it attaches its run leaves a run
// the order never reads, so an act starts a pour only while pourReserve of its
// bound is left. The disposition writer a closed retired PR's bead goes to once
// the act has freed the lock runs past the bound too (Dispositions). A bound
// of zero is no bound.
type Options struct {
	Window time.Duration
	Stop   time.Duration
}

// Reconcile is one run of the landing order. It reads the store once, through a
// ledger pass that lists the beads that carry the marker, closed ones too, and
// every live bead, and decides through that pass each record that carries the
// marker, and each bead on the record that carries a ruling's disposition
// (disposing), an open or blocked one only while it is assigned to nobody or to
// the refinery (mayWork), on the read the PR watch saved on its bead and the
// store. A record that owes no act is reported as its decision found it, with
// no write and no read of GitHub. With Labels set, each PR the live beads own
// whose saved labels differ from the ones the store derives owes a label write
// too (labelPlans), and each PR whose bead's saved read holds a post the city
// has not taken owes its take (takePlans). The records that owe an act, the
// PRs whose labels owe a write and the PRs that owe a take are taken in a
// shuffled order, so one whose act is slow or keeps failing holds no other
// back, and none is started past o.Window. Each
// record's act reads its record again under the record lock, decides it again
// from that read, and acts within o.Stop, its writes guarded on the status and
// assignee it read there. A decision that finds the PR ready has the one-PR
// update re-read it in full once the lock is free, and the act decides again
// on what that read saved before it requests the merge (reread). A label write
// takes no lock and writes nothing on the bead, and stops at o.Stop too. A bead
// whose PR closed under a ruling's disposition goes to the disposition writer
// once the lock is released (dispose). A record that lands on the rig's default
// branch has the branch's seed audit checked once the lock is released, inside
// the window, and its outcome says what the check found. It reports each
// outcome to report as it goes, and returns an error when the listing did not
// answer, or when a record or a PR's labels could not be decided or its act did
// not complete.
func (l Landing) Reconcile(o Options, report func(RunOutcome)) error {
	u := &run{Landing: l}
	start := u.clock()
	plans, err := u.plan()
	if err != nil {
		return err
	}
	failed := 0
	tally := func(out RunOutcome) {
		if out.Action == ActFailed || out.Action == ActRetry {
			failed++
		}
		report(out)
	}
	var acts []string
	writes := map[string]labelWrite{}
	takes := map[string]takeOf{}
	for _, p := range plans {
		switch {
		case p.write != nil:
			writes[p.id] = *p.write
		case p.take != nil:
			takes[p.id] = *p.take
		case !p.due:
			tally(p.out)
			continue
		}
		acts = append(acts, p.id)
	}
	shuffle := l.Shuffle
	if shuffle == nil {
		shuffle = func(ids []string) { rand.Shuffle(len(ids), func(i, j int) { ids[i], ids[j] = ids[j], ids[i] }) }
	}
	shuffle(acts)
	for i, id := range acts {
		if o.Window > 0 && u.clock().Sub(start) > o.Window {
			for _, left := range acts[i:] {
				if w, ok := writes[left]; ok {
					report(RunOutcome{Bead: w.bead, Action: ActLeft, Detail: fmt.Sprintf(
						"the run started no act past its %s, so the next run compares the labels of %s", o.Window, w.url)})
					continue
				}
				if t, ok := takes[left]; ok {
					report(RunOutcome{Bead: t.bead, Action: ActLeft, Detail: fmt.Sprintf(
						"the run started no act past its %s, so the next run makes %s", o.Window, t.of())})
					continue
				}
				report(RunOutcome{Bead: left, Action: ActLeft,
					Detail: fmt.Sprintf("the run started no act past its %s, so the next run acts on the record", o.Window)})
			}
			break
		}
		if w, ok := writes[id]; ok {
			tally(u.writeLabels(w, o.Stop))
			if l.Yield > 0 && i < len(acts)-1 {
				time.Sleep(l.Yield)
			}
			continue
		}
		if t, ok := takes[id]; ok {
			tally(u.take(t, o.Stop))
			if l.Yield > 0 && i < len(acts)-1 {
				time.Sleep(l.Yield)
			}
			continue
		}
		ctx, cancel := bounded(o.Stop)
		u.landed, u.disposal, u.rereadDue, u.reread = nil, nil, "", ""
		out := u.one(ctx, id, o.Stop)
		if u.rereadDue != "" {
			out = u.rereadAndDecide(ctx, id, u.rereadDue, o.Stop)
		}
		cancel()
		if u.disposal != nil {
			out = u.dispose(*u.disposal, out)
		}
		if u.landed != nil {
			out.Detail += u.audit(*u.landed, start, o.Window)
		}
		tally(out)
		if l.Yield > 0 && i < len(acts)-1 {
			time.Sleep(l.Yield)
		}
	}
	if failed > 0 {
		return fmt.Errorf("%d of the run's acts did not complete", failed)
	}
	return nil
}

// clock is the time the run's window is read by: Now, or the system's clock
// when Now is nil.
func (l Landing) clock() time.Time {
	if l.Now == nil {
		return time.Now()
	}
	return l.Now()
}

// disposing reports whether a run reads r for the disposition a ruling
// recorded on it, whatever its marker: r owns a PR on the record, is open or
// blocked, is assigned to nobody or to the refinery and carries a whole
// disposition. rec is r's record.
func (l Landing) disposing(r *ledger.Record, rec record.Record) bool {
	if !record.OnRecord(rec.Result) || !l.mayWork(r) {
		return false
	}
	if s := r.Status(); s != "open" && s != "blocked" {
		return false
	}
	_, whole, err := dispositionOf(r)
	return err == nil && whole
}

// mayWork reports whether r's assignee leaves it to a run: nobody, or the
// refinery. Anyone else assigned r works it now.
func (l Landing) mayWork(r *ledger.Record) bool {
	a := r.Assignee()
	return a == "" || a == l.Refinery
}

// dispositionOf reads the disposition a ruling recorded on r, and whether it
// is whole: a kind the disposition writer closes a bead under, and a
// successor. A disposition that is not whole closes nothing.
func dispositionOf(r *ledger.Record) (Disposition, bool, error) {
	var err error
	get := func(k ledger.Key[string]) string {
		v, _, e := k.Get(r)
		if e != nil && err == nil {
			err = e
		}
		return strings.TrimSpace(v)
	}
	d := Disposition{Kind: get(dispositionKindKey), Successor: get(dispositionSuccessorKey), Store: get(dispositionStoreKey)}
	if err != nil {
		return Disposition{}, false, err
	}
	switch d.Kind {
	case "re-homed", "folded", "fixed-upstream", "duplicate", "not-needed":
		return d, d.Successor != "", nil
	}
	return d, false, nil
}

// read reads the bead from the store itself, closed or not, nil when the store
// holds no such bead.
func (l Landing) read(id string) (*ledger.Record, error) {
	rows, err := l.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return rows[0], nil
}

// run is one run of the landing order, which loads the definition of feedback
// and reads the city's mark and the clone's origin once, when a record first
// needs each, reads the login the city's account acts as once for each host,
// and asks the clone whether one commit contains another once for each pair,
// until it fetches a PR's branch, which fetched names, once for each branch.
// landed is the merge the act just made closed its bead on, for the seed
// audit's check once the lock is free, disposal the close the act just made
// owes the disposition writer once the lock is free, rereadDue the PR the act
// found ready on the saved read, which the one-PR update re-reads once the lock
// is free, reread the bead whose PR the act has had re-read, and audited names,
// for each tip of the default branch the run has checked, the bead whose
// landing checked it.
type run struct {
	Landing
	feedback  Feedback
	mark      string
	origin    *string
	logins    map[string]string
	contains  map[[2]string]bool
	fetched   map[string]bool
	landed    *landedMerge
	disposal  *Disposal
	rereadDue string
	reread    string
	audited   map[string]string
}

// landedMerge is a PR the run closed its bead on: the bead, the PR's number and
// the branch it merged into.
type landedMerge struct {
	bead, number, target string
}

// rule is the definition of feedback, loaded the first time a record needs it.
func (u *run) rule() (Feedback, error) {
	if u.feedback == nil {
		rule, err := u.Feedback()
		if err != nil {
			return nil, err
		}
		u.feedback = rule
	}
	return u.feedback, nil
}

// cityMark is the city's mark, read the first time a dismissal needs it. A mark
// that reads empty, or as more than one line, is no mark.
func (u *run) cityMark() (string, error) {
	if u.mark != "" {
		return u.mark, nil
	}
	if u.Mark == nil {
		return "", errors.New("nothing reads the city's mark")
	}
	m, err := u.Mark()
	if err != nil {
		return "", err
	}
	m = strings.TrimSpace(m)
	if m == "" || strings.Contains(m, "\n") {
		return "", fmt.Errorf("the city's mark read as %q, which is no mark", m)
	}
	u.mark = m
	return m, nil
}

// login is the login the city's account acts as on host, read from hub the
// first time a record on that host needs it, and kept for the rest of the run.
func (u *run) login(host string, hub Hub) (string, error) {
	if l, ok := u.logins[host]; ok {
		return l, nil
	}
	l, err := hub.Login()
	if err != nil {
		return "", err
	}
	if u.logins == nil {
		u.logins = map[string]string{}
	}
	u.logins[host] = l
	return l, nil
}

// originDiffers says why a PR on host in repo is not in the repository the
// clone's origin names, or why the origin did not read, and is empty when the
// PR is in it. The run reads the origin once.
func (u *run) originDiffers(host, repo string) string {
	if u.origin == nil {
		raw, err := u.Checkout.OriginURL()
		if err != nil {
			return "the rig's origin did not read: " + err.Error()
		}
		u.origin = &raw
	}
	return outsideOrigin(*u.origin, host, repo)
}

// holds reports whether commit contains ancestor in the clone's history, asked
// once for each pair in a run.
func (u *run) holds(commit, ancestor string) (bool, error) {
	k := [2]string{commit, ancestor}
	if v, ok := u.contains[k]; ok {
		return v, nil
	}
	v, err := u.Checkout.Contains(commit, ancestor)
	if err != nil {
		return false, err
	}
	if u.contains == nil {
		u.contains = map[[2]string]bool{}
	}
	u.contains[k] = v
	return v, nil
}

// fetchBranch fetches a PR's branch into the clone once a run, stopped when ctx
// ends. A commit it brings can contain one the clone showed none to, so each
// answer that a commit does not contain another is asked again.
func (u *run) fetchBranch(ctx context.Context, branch string) error {
	if u.fetched[branch] {
		return nil
	}
	if err := u.Checkout.FetchBranch(ctx, branch); err != nil {
		return err
	}
	if u.fetched == nil {
		u.fetched = map[string]bool{}
	}
	u.fetched[branch] = true
	maps.DeleteFunc(u.contains, func(_ [2]string, in bool) bool { return !in })
	return nil
}

// state is one record as a run read it: the bead's row and its record, the
// provenance instant the definition of feedback is applied from, the beads its
// blocks edges name, open and closed, the withdrawals filed on it and the review
// runs attached to it, live, and the disposition a ruling recorded on it, with
// ruled saying whether it is whole (dispositionOf). reads is the ledger the
// decision reads the store through: the run's pass when it plans, a fresh pass
// under the lock.
type state struct {
	id, status, assignee, branch string
	since                        string
	row                          *ledger.Record
	rec                          record.Record
	disposition                  Disposition
	ruled                        bool
	blockers                     []*ledger.Record
	withdrawals                  []withdrawal
	runs                         []string
	now                          string
	reads                        *ledger.Ledger
}

// carriedOut is what carrying out a record's withdrawals did: its account, for
// the record's outcome, whether a withdrawal is still open, and whether a step
// of it did not complete, such as a dismissal GitHub did not answer.
type carriedOut struct {
	note         string
	held, failed bool
}

// act is the work a run does on one record, given what carrying out its
// withdrawals did first.
type act func(ctx context.Context, c carriedOut) RunOutcome

// plan is what a record owes: an act, or none, with the outcome that says why.
// reread says the record reads ready for its merge, which the act decides
// again once the one-PR update has re-read the PR in full (rereadAndDecide).
// In a run's list of plans, due says the record owes an act, which its act
// decides again under the record lock (one), a PR whose labels owe a write is
// planned under its URL, with write holding the write, and a PR that owes a
// take is planned under its bead's id with the word take before it, with take
// holding the take.
type plan struct {
	id     string
	out    RunOutcome
	act    act
	reread bool
	due    bool
	write  *labelWrite
	take   *takeOf
}

func none(s state, action, detail string) plan {
	return plan{out: RunOutcome{Bead: s.id, Action: action, Detail: detail}}
}

func doing(a act) plan { return plan{act: a} }

// plan reads the store once, through a pass that lists the beads that carry the
// marker, closed ones too, and then, when there is one or the run keeps the
// PRs' labels, every live bead, and the live beads that carry a ruling's
// disposition, through the same pass or, when the pass holds no live bead,
// through a read of their own. It decides through the pass each marked record
// that is closed, or open or blocked and assigned to nobody or to the refinery
// (mayWork), and each bead it reads for its disposition (disposing). A record
// that owes no act gets its outcome, and one that owes an act, or that the pass
// could not decide, because its state or a read its decision makes did not
// answer, is due, for its act to decide again under the record lock (one). It leaves out a bead that anyone else is assigned, since a
// run writes nothing to it. A record that does not read as a record is not one
// the run can act on. The takes the owned PRs owe follow (takePlans), and with
// Labels set, the label writes they owe (labelPlans). The plans are in id
// order.
func (u *run) plan() ([]plan, error) {
	pass := u.Ledger.Pass()
	rows, err := pass.Find(record.Marked())
	if err != nil {
		return nil, err
	}
	every := len(rows) > 0 || u.Labels != nil
	if every {
		if _, err := pass.Find(ledger.Every()); err != nil {
			return nil, err
		}
	}
	ruled, err := pass.Find(ledger.Carrying(dispositionKindKey))
	if err != nil {
		return nil, err
	}
	if !every {
		if len(ruled) == 0 {
			return u.takePlans(pass)
		}
		if _, err := pass.Find(ledger.Every()); err != nil {
			return nil, err
		}
	}
	var due []*ledger.Record
	listed := map[string]bool{}
	for _, r := range rows {
		rec, err := record.Read(r)
		if err != nil || !rec.Marked {
			continue
		}
		switch r.Status() {
		case "open", "blocked":
			if !u.mayWork(r) {
				continue
			}
		case "closed":
		default:
			continue
		}
		due, listed[r.ID] = append(due, r), true
	}
	for _, r := range ruled {
		rec, err := record.Read(r)
		if err != nil || listed[r.ID] || !u.disposing(r, rec) {
			continue
		}
		due = append(due, r)
	}
	// Each record's state reads the beads its blocks edges name, closed ones
	// among them, which the pass's read of every live bead does not hold. One
	// read here holds them for every record the run reads, so a run's reads do
	// not grow with its records. A read that fails here leaves each record's
	// state to read its own, and a record whose state does not read is due.
	var named []string
	for _, r := range due {
		if s := r.Status(); (s == "open" || s == "blocked") && u.mayWork(r) {
			ids, _ := blockerIDs(r)
			for _, id := range ids {
				if !slices.Contains(named, id) {
					named = append(named, id)
				}
			}
		}
	}
	if len(named) > 0 {
		_, _ = pass.Find(ledger.ByID(named...).WithClosed())
	}
	var out []plan
	for _, r := range due {
		s, missed := u.state(pass, r)
		if missed == nil {
			p := u.decide(s)
			if p.act == nil && !p.reread && p.out.Action != ActRetry && p.out.Action != ActFailed {
				if p.out.Bead == "" {
					p.out.Bead = r.ID
				}
				out = append(out, plan{id: r.ID, out: p.out})
				continue
			}
		}
		out = append(out, plan{id: r.ID, due: true})
	}
	takes, err := u.takePlans(pass)
	if err != nil {
		return nil, err
	}
	out = append(out, takes...)
	if u.Labels != nil {
		writes, err := u.labelPlans(pass)
		if err != nil {
			return nil, err
		}
		out = append(out, writes...)
	}
	slices.SortFunc(out, func(a, b plan) int { return strings.Compare(a.id, b.id) })
	return out, nil
}

// state reads the record r carries, through l: its record, the disposition a
// ruling recorded on it, its branch and provenance instant, and for an open or
// blocked bead assigned to nobody or to the refinery, what its blocks edges
// name. A bead whose record no longer carries the marker, unless a run reads it
// for its disposition (disposing), or whose parts do not read, gets the outcome
// that says so in place of a state.
func (u *run) state(l *ledger.Ledger, r *ledger.Record) (state, *RunOutcome) {
	id := r.ID
	failed := func(why string, err error) (state, *RunOutcome) {
		return state{}, &RunOutcome{Bead: id, Action: ActFailed, Detail: why + " did not read: " + err.Error()}
	}
	rec, err := record.Read(r)
	if err != nil {
		return failed("the record", err)
	}
	d, ruled, err := dispositionOf(r)
	if err != nil {
		return failed("the disposition", err)
	}
	if !rec.Marked && !u.disposing(r, rec) {
		return state{}, &RunOutcome{Bead: id, Action: ActSkipped, Detail: "the bead no longer carries the marker"}
	}
	branch, _, err := record.Branch.Get(r)
	if err != nil {
		return failed("the branch", err)
	}
	since, _, err := provenanceKey.Get(r)
	if err != nil {
		return failed("the provenance instant", err)
	}
	s := state{id: id, status: r.Status(), assignee: r.Assignee(), branch: strings.TrimSpace(branch),
		since: strings.TrimSpace(since), row: r, rec: rec, disposition: d, ruled: ruled, now: u.stamp(), reads: l}
	if (s.status != "open" && s.status != "blocked") || !u.mayWork(r) {
		return s, nil
	}
	rows, err := blockersIn(l, r, true)
	if err == nil {
		s.blockers = rows
		s.withdrawals, err = withdrawalsIn(rows)
	}
	if err == nil {
		s.runs, err = runsIn(rows)
	}
	if err != nil {
		return failed("what holds the bead", err)
	}
	return s, nil
}

// one acts on one record: under the record lock it reads the record afresh,
// decides it from that read and the read the PR watch saved on the bead, and
// makes the act it owes, stopped once ctx, which ends stop after the act
// starts, ends, its reads and writes of the store among what the stop ends. It
// waits for the lock no longer than what is left of ctx, since the lock does
// not watch ctx, and a merge's act takes it a second time after the re-read. A
// lock that does not come free inside that wait, or an act the stop ended, is
// an act that did not complete. A decision that finds the PR ready for a merge
// the act has not had re-read names the PR in rereadDue, and the run has it
// re-read once the lock is free (rereadAndDecide).
func (u *run) one(ctx context.Context, id string, stop time.Duration) RunOutcome {
	// Acts run one at a time, so the run's ledger is the act's for its length.
	unbound := u.Ledger
	u.Ledger = unbound.Within(ctx)
	defer func() { u.Ledger = unbound }()
	release, err := record.Lock(u.Dir, lockWait(ctx, u.Wait))
	if err != nil {
		return RunOutcome{Bead: id, Action: ActRetry, Detail: "the record lock did not come free, so the next run acts: " + err.Error()}
	}
	defer release()
	r, err := u.read(id)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the bead did not read: " + err.Error()}
	}
	if r == nil {
		return RunOutcome{Bead: id, Action: ActSkipped, Detail: "the store no longer holds the bead"}
	}
	s, missed := u.state(u.Ledger.Pass(), r)
	p := plan{}
	if missed != nil {
		p.out = *missed
	} else {
		p = u.decide(s)
	}
	out := p.out
	switch {
	case p.reread:
		u.rereadDue = s.rec.URL
	case p.act != nil:
		out = p.act(ctx, carriedOut{})
	}
	if out.Bead == "" {
		out.Bead = id
	}
	if ctx.Err() != nil && (out.Action == ActRetry || out.Action == ActFailed) {
		out.Action = ActRetry
		out.Detail = fmt.Sprintf("the act was stopped at its %s: %s", stop, out.Detail)
	}
	return out
}

// rereadAndDecide is the check a merge makes of GitHub before it is requested,
// the one act a run checks first: with the record lock free, the one-PR update
// re-reads the PR at url in full and saves what it read, and the act then
// decides the record again under the lock, on what the update saved, so the
// merge it requests is pinned to the head that read judged. A re-read that
// finds the PR not ready leaves the saved read corrected, so the next run finds
// no merge to check. A re-read that does not save requests nothing, and the
// next run decides again. It runs within ctx, the act's.
func (u *run) rereadAndDecide(ctx context.Context, id, url string, stop time.Duration) RunOutcome {
	u.rereadDue = ""
	retry := func(why string) RunOutcome {
		if ctx.Err() != nil {
			why = fmt.Sprintf("the act was stopped at its %s: %s", stop, why)
		}
		return RunOutcome{Bead: id, Action: ActRetry, Detail: "the PR reads ready on the saved read, and " + why +
			", so no merge is requested; the next run decides again"}
	}
	if u.Reread == nil {
		return retry("nothing re-reads it here before its merge")
	}
	if err := u.Reread(ctx, url); err != nil {
		return retry("the one-PR update's re-read of it did not save: " + err.Error())
	}
	u.reread = id
	return u.one(ctx, id, stop)
}

// lockWait is how long an act waits for the record lock: wait, or what is left
// of ctx when that is less, since the lock does not watch ctx.
func lockWait(ctx context.Context, wait time.Duration) time.Duration {
	if end, ok := ctx.Deadline(); ok {
		if left := max(time.Until(end), 0); wait <= 0 || left < wait {
			return left
		}
	}
	return wait
}

// bounded is a context that ends stop from now, or one that never ends when
// stop is zero.
func bounded(stop time.Duration) (context.Context, context.CancelFunc) {
	if stop > 0 {
		return context.WithTimeout(context.Background(), stop)
	}
	return context.Background(), func() {}
}

// decide is what the record s read owes, on the store and the read the PR watch
// saved on the bead. It reads no GitHub.
func (u *run) decide(s state) plan {
	switch {
	case s.status == "closed":
		return u.decideClosed(s)
	case !u.mayWork(s.row):
		return none(s, ActAssigned, fmt.Sprintf("assigned to %s, who works it now, so nothing is written, no merge "+
			"is requested and no review run is poured; a later run works it once the assignee is gone", s.assignee))
	case s.status != "open" && s.status != "blocked":
		return none(s, ActSkipped, "the bead's status "+s.status+" is none the record knows")
	case s.ruled && record.OnRecord(s.rec.Result):
		return u.decideDisposed(s)
	case s.status == "open":
		return u.decideOpen(s)
	}
	return u.decideBlocked(s)
}

// commit makes w, guarded on what the run read, and names the outcome: done
// when it landed, moved when bd's guard refused it, failed otherwise.
func (u *run) commit(s state, w *ledger.Write, done RunOutcome) RunOutcome {
	w.Guard(s.status, s.assignee)
	if err := u.Ledger.Commit(w); err != nil {
		if errors.Is(err, ledger.ErrGuard) {
			return RunOutcome{Bead: s.id, Action: ActMoved,
				Detail: "the bead moved since this run read it, so nothing landed: " + done.Detail}
		}
		return RunOutcome{Bead: s.id, Action: ActFailed, Detail: done.Detail + ", but the write did not land: " + err.Error()}
	}
	return done
}

// decideClosed decides a closed bead that still carries the marker. One closed
// on a verified merge owes nothing more, and its marker clears. Any other is a
// close that took no lock and reached the bead with no verified merge, which a
// run reopens as blocked, behind a gate.
func (u *run) decideClosed(s state) plan {
	if s.rec.Result == record.Merged && mergeEvidence(s.rec) {
		return doing(func(context.Context, carriedOut) RunOutcome {
			w := u.Ledger.Write(s.id)
			record.Unmark(w)
			return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActSettled,
				Detail: "closed on a verified merge at " + s.rec.MergedSHA + ": the marker is cleared"})
		})
	}
	pr := firstOf(s.rec.URL, s.rec.ExistingPR, "its pull request")
	return u.excepting(s, record.LegacyClosed,
		fmt.Sprintf("%s closed while it carried the pending record of %s, with no verified merge", s.id, pr),
		fmt.Sprintf("%s was closed while it still carried the pending record of %s, and no merge was verified, so "+
			"the landing order reopened it as blocked, and what waits on it stays held. Check whether the pull "+
			"request merged into its target. If it did, close %s again as landed. If it did not, decide whether "+
			"the work goes back to the refinery or stands down.", s.id, pr, s.id))
}

// decideOpen decides an open bead assigned to nobody or to the refinery. A
// changed head is held from the refinery while a withdrawal is open on the
// bead, which the run carries out, or while a review run is attached to it,
// whose end a later run reads, and the marker stays until then. Once neither
// holds it, the run hands it to the refinery (handOver). A whole record whose
// second write landed moves to blocked and to nobody, and is decided on.
// Anything else is a record a dead writer left half written, which goes back
// to the refinery for its full validation.
func (u *run) decideOpen(s state) plan {
	switch {
	case s.rec.Result == record.HeadChanged && withdrawing(s):
		return u.decideRequeued(s)
	case s.rec.Result == record.HeadChanged && len(s.runs) > 0:
		return none(s, ActChecked, onRuns(s))
	case s.rec.Result == record.HeadChanged:
		return doing(func(ctx context.Context, _ carriedOut) RunOutcome {
			return u.handOver(ctx, s, ActSettled, "its changed head waits on the refinery's validation")
		})
	case s.rec.Result == record.Pending && len(recordGaps(s.rec, s.branch)) == 0:
		return doing(func(ctx context.Context, c carriedOut) RunOutcome {
			w := u.Ledger.Write(s.id)
			record.Block(w)
			done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActBlocked, Detail: "the whole record had landed on an open bead"})
			if done.Action != ActBlocked {
				return done
			}
			s.status, s.assignee = "blocked", ""
			next := u.decideBlocked(s)
			if next.reread {
				u.rereadDue = s.rec.URL
			}
			if next.act == nil {
				if next.out.Bead == "" {
					next.out.Bead = s.id
				}
				return next.out
			}
			return next.act(ctx, c)
		})
	}
	return doing(func(context.Context, carriedOut) RunOutcome {
		w := u.Ledger.Write(s.id)
		record.Revalidate(w, "Interrupted PR handoff record is incomplete; full refinery validation is required", u.Refinery)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRevalidate,
			Detail: "the record was half written: the bead goes back to the refinery, and no merge is requested"})
	})
}

// withdrawing reports whether a withdrawal is open on the record s read.
func withdrawing(s state) bool {
	return slices.ContainsFunc(s.withdrawals, func(w withdrawal) bool { return w.open })
}

// seen is the PR the record names as the read the PR watch saved on the bead
// shows it, with the host the record names, which an act's reads and requests
// go to.
type seen struct {
	host string
	pr   *gh.PullRequest
}

// seenPR is the PR the record s read names, as the read the PR watch saved on
// the bead shows it. It returns the plan in its place when there is nothing to
// decide on: the PR is outside the rig's own repository, which no act may
// reach, so the next run decides again; the bead holds no saved read of the
// record's PR, as before the PR watch's first pass over it, so the record waits
// for the watch's next pass, which saves one (moved); or the saved read shows
// a PR other than the one the record names, by its URL, head branch or base,
// which is the record's exception.
func (u *run) seenPR(s state) (seen, *plan) {
	r := s.rec
	host, _, number, _ := record.ParseURL(r.URL)
	if why := u.originDiffers(host, r.Repo); why != "" {
		p := none(s, ActRetry, why+"; the next run decides again")
		return seen{}, &p
	}
	saved, _, err := githubReadKey.Get(s.row)
	if err != nil || saved == nil || saved.PR == nil || !strings.EqualFold(saved.PR.Repository, r.Repo) ||
		saved.PR.Number != number {
		p := none(s, ActChecked, "the bead holds no saved read of the PR yet, so the record waits for the PR "+
			"watch's next pass to save one")
		return seen{}, &p
	}
	pr := saved.PR.pullRequest()
	if ids := identityGaps(pr, r.URL, number, r.Repo, s.branch, r.Target); len(ids) > 0 {
		p := u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
		return seen{}, &p
	}
	return seen{host: host, pr: pr}, nil
}

// unknownState is the plan for a PR whose state the saved read gives as none
// the record knows.
func unknownState(s state, state string) plan {
	return none(s, ActRetry, fmt.Sprintf("the saved read gives the PR's state as %q, which is no state the record "+
		"knows; the next run decides again", state))
}

// decideRequeued decides, on the saved read, a changed head that a withdrawal
// open on the bead holds from the refinery. It carries the withdrawal out while
// the PR is open, keeping the marker while a withdrawal is open or a review run
// is attached, so the bead goes to the refinery once nothing the order owes
// holds it (handOver). A PR that closed or merged meanwhile is the record's
// exception, as on a pending record.
func (u *run) decideRequeued(s state) plan {
	r := s.rec
	if missing := recordGaps(r, s.branch); len(missing) > 0 {
		return u.invalid(s, "the requeued record is incomplete: it lacks "+strings.Join(missing, ", "))
	}
	f, stop := u.seenPR(s)
	if stop != nil {
		return *stop
	}
	switch f.pr.State {
	case "OPEN":
		return u.withCarry(s, f, doing(func(ctx context.Context, c carriedOut) RunOutcome {
			if c.held || len(s.runs) > 0 {
				action := ActChecked
				if c.failed {
					action = ActRetry
				}
				detail := "its changed head waits on the refinery, behind the withdrawal: " + c.note
				if !c.held {
					detail = withNote(onRuns(s), c.note)
				}
				return RunOutcome{Bead: s.id, Action: action, Detail: detail}
			}
			return u.handOver(ctx, s, ActSettled, withNote("its changed head waits on the refinery's validation", c.note))
		}))
	case "CLOSED":
		return u.excepting(s, record.ClosedUnmerged, "Pull request "+r.URL+" closed without merging.",
			fmt.Sprintf("Pull request %s closed without merging while a withdrawal of its approvals was open, so %s stays "+
				"blocked, and what waits on it stays held. Decide what becomes of the work: reopen the pull request and "+
				"send %s back to the refinery, or stand the work down.", r.URL, s.id, s.id))
	case "MERGED":
		return u.decideMerged(s, f.pr)
	}
	return unknownState(s, f.pr.State)
}

// decideBlocked decides a blocked bead: the record must be whole and must read
// pending, or a verified merge whose close did not land. Its PR is decided on
// the saved read.
func (u *run) decideBlocked(s state) plan {
	r := s.rec
	if record.Exception(r.Result) {
		// A run recorded the exception and stopped before its gate filed.
		message := fmt.Sprintf("%s %s stays blocked, and what waits on it stays held, until a person "+
			"decides what becomes of the work.", firstOf(r.BlockedReason, "The pending record met "+r.Result+"."), s.id)
		if r.Result == record.CloseRefused {
			message = refusedMessage(s.id, firstOf(r.BlockedReason, "A verified merge's close was refused"))
		}
		return doing(func(ctx context.Context, _ carriedOut) RunOutcome {
			return u.gate(ctx, s, r.Result, message,
				RunOutcome{Bead: s.id, Action: ActExcepted, Detail: r.Result + ": the gate an earlier run did not file is filed"})
		})
	}
	switch r.Result {
	case record.Pending:
		if missing := recordGaps(r, s.branch); len(missing) > 0 {
			return u.invalid(s, "the pending record is incomplete: it lacks "+strings.Join(missing, ", "))
		}
		if r.MergedSHA != "" || r.MergedAt != "" {
			return u.invalid(s, "the pending record carries a merge's evidence")
		}
	case record.Merged:
		if !mergeEvidence(r) || len(recordGaps(r, s.branch)) > 0 {
			return u.invalid(s, "the record names a merge without its whole evidence")
		}
	default:
		return u.invalid(s, fmt.Sprintf("a blocked bead with a pending marker reads merge_result %q, not %s", r.Result, record.Pending))
	}
	f, stop := u.seenPR(s)
	if stop != nil {
		return *stop
	}
	p := f.pr
	if !record.IsObjectID(p.HeadRefOid) {
		return u.invalid(s, fmt.Sprintf("GitHub names the PR's head %q, which is no commit id", p.HeadRefOid))
	}
	switch p.State {
	case "OPEN":
		if r.Result == record.Merged {
			return u.contradiction(s, fmt.Sprintf("%s recorded a merge at %s, and GitHub reports the PR open", s.id, r.MergedSHA))
		}
		if p.HeadRefOid != r.Head {
			return u.decideHeadChanged(s, f)
		}
		return u.decideAtHead(s, f)
	case "CLOSED":
		return u.excepting(s, record.ClosedUnmerged, "Pull request "+r.URL+" closed without merging.",
			fmt.Sprintf("Pull request %s closed without merging, so %s stays blocked, and what waits on it stays "+
				"held. Decide what becomes of the work: reopen the pull request and send %s back to the refinery, "+
				"or stand the work down.", r.URL, s.id, s.id))
	case "MERGED":
		return u.decideMerged(s, p)
	}
	return unknownState(s, p.State)
}

// decideDisposed decides a bead on the record that carries the disposition a
// ruling recorded before it closed the PR (pr-dispose.sh), on the saved read.
// The PR will not land, so the run requests no merge, pours no review run,
// marks nothing ready and carries out no withdrawal, whatever GitHub says of
// it. One still open waits for its close, one that merged all the same lands as
// any merge does, and one that has closed is retired (decideRetired).
func (u *run) decideDisposed(s state) plan {
	r := s.rec
	if missing := recordGaps(r, s.branch); len(missing) > 0 {
		return u.invalid(s, "the record is incomplete: it lacks "+strings.Join(missing, ", "))
	}
	f, stop := u.seenPR(s)
	if stop != nil {
		return *stop
	}
	switch f.pr.State {
	case "OPEN":
		return none(s, ActChecked, s.disposition.ruling()+", so no merge is requested, and the PR's close finishes it")
	case "CLOSED":
		return u.decideRetired(s, f.pr.Number)
	case "MERGED":
		return u.decideMerged(s, f.pr)
	}
	return unknownState(s, f.pr.State)
}

// decideRetired decides a PR a ruling retired once the saved read shows it
// closed. While a review run is attached to the bead, the bead's close waits
// for the run to end. Otherwise the act closes the withdrawals and the asks
// still open on the bead, which nothing carries out or takes once the PR is
// closed, and owes the bead's own close to the disposition writer, which
// Reconcile hands it once the lock is free, with the status and assignee the
// act judged it under (dispose). A close of a withdrawal or an ask that does
// not land leaves the bead to the next run.
func (u *run) decideRetired(s state, number int) plan {
	d := s.disposition
	closed := "the PR closed, and " + d.ruling()
	if len(s.runs) > 0 {
		return none(s, ActChecked, fmt.Sprintf("%s; the bead's close waits for the review run %s to end", closed, strings.Join(s.runs, ", ")))
	}
	asks, err := review.AsksIn(s.reads, s.row, s.blockers)
	if err != nil {
		return none(s, ActRetry, closed+"; the asks on the bead did not read, and the next run decides again: "+err.Error())
	}
	return doing(func(context.Context, carriedOut) RunOutcome {
		why := fmt.Sprintf("PR #%d closed under the disposition a ruling recorded on %s, %s onto %s", number, s.id, d.Kind, d.Successor)
		var moot []string
		for _, w := range s.withdrawals {
			if !w.open {
				continue
			}
			note := fmt.Sprintf("The landing order closed this withdrawal (%s): %s, so no approval it withdraws can merge it.", s.now, why)
			if err := u.moot(w.id, w.status, w.assignee, note); err != nil {
				return RunOutcome{Bead: s.id, Action: ActRetry,
					Detail: fmt.Sprintf("%s; the withdrawal %s did not close, and the next run acts again: %v", closed, w.id, err)}
			}
			moot = append(moot, w.id)
		}
		for _, a := range asks {
			if !a.Open() {
				continue
			}
			note := fmt.Sprintf("The landing order closed this ask (%s): %s, so no review run takes it.", s.now, why)
			if err := u.moot(a.ID, a.Status, "", note); err != nil {
				return RunOutcome{Bead: s.id, Action: ActRetry,
					Detail: fmt.Sprintf("%s; the ask %s did not close, and the next run acts again: %v", closed, a.ID, err)}
			}
			moot = append(moot, a.ID)
		}
		detail := closed
		if len(moot) > 0 {
			detail += fmt.Sprintf("; %s closed, which nothing takes now", strings.Join(moot, ", "))
		}
		u.disposal = &Disposal{Bead: s.id, Status: s.status, Assignee: s.assignee, Disposition: d,
			Note: fmt.Sprintf("PR #%d closed under the disposition a ruling recorded before the close", number)}
		return RunOutcome{Bead: s.id, Action: ActChecked, Detail: detail + "; the bead goes to the disposition writer"}
	})
}

// moot closes a bead the retired PR leaves nothing to do for, guarded on the
// status and assignee the run read, with note saying why. It is a plain task,
// whose close the runtime's work-record gate reads, and closing it ships no
// commit, so its record is no-op.
func (u *run) moot(id, status, assignee, note string) error {
	w := u.Ledger.Write(id)
	w.Guard(status, assignee)
	w.Status("closed")
	w.WorkRecord("no-op", "", "")
	w.Note(note)
	return u.Ledger.Commit(w)
}

// dispose hands the close of a bead whose PR closed under a ruling's
// disposition to the disposition writer, with the record lock free, and says
// what became of it: out, what the act did under the lock, with the writer's
// answer after it. A close the writer holds for now, such as one an open wait
// on the bead holds, or the close of a bead reassigned or ruled again since the
// act judged it, waits for the next run, which reads the bead again under the
// lock, so it reports as checked. The writer runs to its end, past the act's
// bound (Dispositions).
func (u *run) dispose(x Disposal, out RunOutcome) RunOutcome {
	if u.Dispositions == nil {
		return RunOutcome{Bead: x.Bead, Action: ActFailed, Detail: out.Detail + ", but no disposition writer is set"}
	}
	err := u.Dispositions.Close(x)
	var held *HeldClose
	switch {
	case err == nil:
		return RunOutcome{Bead: x.Bead, Action: ActDisposed, Detail: out.Detail + ", which closed it"}
	case errors.As(err, &held):
		return RunOutcome{Bead: x.Bead, Action: ActChecked,
			Detail: out.Detail + ", which holds its close for now, and the next run reads it again: " + held.Why}
	}
	return RunOutcome{Bead: x.Bead, Action: ActFailed, Detail: out.Detail + ", which did not answer: " + err.Error()}
}

// decideHeadChanged decides a PR the saved read shows open at a head other
// than the one the refinery validated. The saved read can lag a push, since the
// refinery pushes a head before it records it and the PR watch saves the push
// at its next pass, and the refinery validates whatever its preparation
// fetched, a branch a person rewrote included, so the head the saved read gives
// need not be on the validated head's history. So the act fetches the PR's
// branch and reads its tip before it sends anything back. A tip at the head the
// saved read gives confirms it, and the bead goes back to the refinery at it. A
// tip that contains the validated head says the saved read lags the branch:
// nothing is sent back, and a later run decides on the head the watch saves.
// Any other tip is a branch moved off the validated head, which goes back to
// the refinery at that tip. A fetch or a read that does not answer sends
// nothing back, so the next run decides again. A bead goes back after its
// withdrawals (sendBack).
func (u *run) decideHeadChanged(s state, f seen) plan {
	r, seen := s.rec, f.pr.HeadRefOid
	return u.withCarry(s, f, doing(func(ctx context.Context, c carriedOut) RunOutcome {
		at := fmt.Sprintf("the saved read gives the PR's head as %s, not the validated %s", seen, r.Head)
		retry := func(why string) RunOutcome {
			return RunOutcome{Bead: s.id, Action: ActRetry,
				Detail: withNote(at+", and "+why+", so nothing is sent back; the next run decides again", c.note)}
		}
		if err := u.fetchBranch(ctx, s.branch); err != nil {
			return retry(fmt.Sprintf("origin/%s did not fetch: %v", s.branch, err))
		}
		tip, err := u.Checkout.Tip(s.branch)
		if err != nil {
			return retry("the branch's tip did not read: " + err.Error())
		}
		if tip == seen {
			return u.sendBack(ctx, s, seen, fmt.Sprintf("origin/%s is at %s", s.branch, tip), c)
		}
		landed, err := u.holds(tip, r.Head)
		if err != nil {
			return retry(fmt.Sprintf("whether origin/%s at %s contains the validated head did not read: %v", s.branch, tip, err))
		}
		if !landed {
			return u.sendBack(ctx, s, tip, fmt.Sprintf("origin/%s is at %s, which does not contain the validated head", s.branch, tip), c)
		}
		return RunOutcome{Bead: s.id, Action: ActChecked, Detail: withNote(fmt.Sprintf("%s, and origin/%s at %s "+
			"contains the validated head, so the saved read lags the branch and nothing is sent back; a later run "+
			"decides on the head the PR watch saves", at, s.branch, tip), c.note)}
	}))
}

// sendBack records the bead's changed head at seen, the head the act found in
// place of the one the refinery validated, once the act has carried out the
// record's withdrawals as c says, and hands the head to the refinery.
// The bead keeps its marker, assigned to nobody, while a withdrawal is still
// open or a review run is attached, and until the hand-over has assigned the
// bead to a refinery that nothing else tells of the head and woken it
// (handOver). shown, when set, says for the outcome what showed that the head
// is not the validated one.
func (u *run) sendBack(ctx context.Context, s state, seen, shown string, c carriedOut) RunOutcome {
	r := s.rec
	reason := fmt.Sprintf("PR head changed after refinery validation (%s -> %s); quality gates must run again", r.Head, seen)
	said := reason
	if shown != "" {
		said = reason + "; " + shown
	}
	detail := withNote(said, c.note)
	if !c.held && len(s.runs) > 0 {
		detail = withNote(said+"; "+onRuns(s), c.note)
	}
	// The requeue keeps the marker, and the bead assigned to nobody, while a
	// withdrawal or an attached run holds the changed head, and for the
	// hand-over that assigns the bead to the refinery and wakes it once the
	// requeue lands, or that reads what holds the bead again when this read
	// fails. Otherwise its own write hands the head to the refinery.
	watched := c.held || len(s.runs) > 0
	var holds []hold
	var unread error
	if !watched {
		holds, unread = u.mergeHolds(s)
	}
	keep := watched || unread != nil || len(holds) > 0
	to, done := u.Refinery, RunOutcome{Bead: s.id, Action: ActRequeued, Detail: detail + "; the bead is assigned to the refinery"}
	if keep {
		to, done.Detail = "", detail
	}
	w := u.Ledger.Write(s.id)
	record.Requeue(w, r.URL, seen, reason, to)
	done = u.commit(s, w, done)
	if done.Action != ActRequeued || !keep || watched {
		return done
	}
	s.status = "open"
	if unread != nil {
		return u.handOverLater(s, detail, "what holds the bead did not read, so the next run reads it again: "+unread.Error())
	}
	return u.wakeAndSettle(ctx, s, holds, ActRequeued, detail)
}

// decideAtHead decides a PR the saved read shows open at the validated head. A
// PR already in its base's merge queue owes nothing. A draft the review loop
// has passed at its head, with no review run attached and no ask a run can
// take, is marked ready, and a later run decides it on the read the PR watch
// saves then (readyBar). Otherwise the evaluator decides on the saved read
// whether the PR is ready (fromSaved), and a saved read that is not current for
// the bead waits for the watch's next pass. One it finds not ready is owed a
// review run when it has no passed result at the head or an ask a run can take
// is open, which the run pours (admit). One it finds ready is checked against
// GitHub before its merge: the act has the one-PR update re-read the PR in
// full, decides again on what that read saved (rereadAndDecide), and merges
// only on that read, pinned to the head the evaluator judged there (merge).
func (u *run) decideAtHead(s state, f seen) plan {
	p := f.pr
	if p.InMergeQueue {
		return u.withCarry(s, f, none(s, ActChecked, "the PR is in its base's merge queue, which holds its merge request"))
	}
	asks, err := review.AsksIn(s.reads, s.row, s.blockers)
	if err != nil {
		return none(s, ActRetry, "the asks on the bead did not read; the next run decides again: "+err.Error())
	}
	if p.IsDraft {
		results, _, err := review.Results.Get(s.row)
		if err != nil {
			return none(s, ActRetry, "the review results did not read; the next run decides again: "+err.Error())
		}
		if readyBar(s, p, results, asks) == "" {
			return u.withCarry(s, f, doing(func(ctx context.Context, c carriedOut) RunOutcome {
				if err := u.Hub(ctx, f.host).MarkReady(p.ID); err != nil {
					return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(fmt.Sprintf("the ready transition at %s "+
						"was refused or not answered, and the next run decides again: %v", p.HeadRefOid, err), c.note)}
				}
				return RunOutcome{Bead: s.id, Action: ActReadied, Detail: withNote(fmt.Sprintf("marked ready at %s, without "+
					"waiting for CI: a passed result names the head, and no review run is attached and no ask a run can "+
					"take is open", p.HeadRefOid), c.note)}
			}))
		}
	}
	ans, err := fromSaved(s.reads, s.id)
	if err != nil {
		return none(s, ActRetry, "the evaluator's read of the store did not answer; the next run decides again: "+err.Error())
	}
	if !ans.Ready {
		if i := slices.IndexFunc(ans.Conditions, func(c Condition) bool { return c.Kind == KindGitHubUnread }); i >= 0 {
			return u.withCarry(s, f, none(s, ActChecked, ans.Conditions[i].Detail+"; the record waits for the PR "+
				"watch's next pass, which reads the PR whole"))
		}
		if owed, ok := u.admit(s, ans, asks); ok {
			return u.withCarry(s, f, owed)
		}
		var not []string
		for _, c := range ans.Conditions {
			not = append(not, string(c.Kind))
		}
		return u.withCarry(s, f, none(s, ActChecked, "not ready: "+strings.Join(slices.Compact(not), ", ")))
	}
	if u.reread != s.id {
		return plan{reread: true, out: RunOutcome{Bead: s.id, Action: ActChecked,
			Detail: "ready on the saved read, so the one-PR update re-reads the PR before its merge"}}
	}
	return u.withCarry(s, f, doing(func(ctx context.Context, c carriedOut) RunOutcome { return u.merge(ctx, s, f, ans, c) }))
}

// merge asks GitHub to merge a PR the evaluator found ready on the read the
// one-PR update saved once it had re-read the PR in full for this act, pinned to
// the head the answer judged, or to add it to its base's merge queue where the
// base requires one. Whatever GitHub answers, the next run decides the PR again.
func (u *run) merge(ctx context.Context, s state, f seen, ans Answer, c carriedOut) RunOutcome {
	// The merge request is the one act no guard can take back, so the bead is
	// read once more just before it: a close or an assignment that took no lock
	// and landed during the act's reads stops it here. One that lands after this
	// read is the residual the design names, a merge requested before the run
	// could read the assignment. A ruling's disposition takes the record lock, so
	// none lands while the act holds it: one recorded before the act read the
	// bead under the lock took the act to decideDisposed, and one that comes
	// later waits for the lock and lands after the request.
	now, err := u.read(s.id)
	if err != nil {
		return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote("the bead did not read again before the merge "+
			"request; the next run decides again: "+err.Error(), c.note)}
	}
	if now == nil || now.Status() != s.status || now.Assignee() != s.assignee {
		return RunOutcome{Bead: s.id, Action: ActMoved, Detail: withNote(
			"the bead moved during the act's reads, so no merge was requested; the next run reads it as it stands", c.note)}
	}
	hub := u.Hub(ctx, f.host)
	method, ask := "merge", hub.MergePullRequest
	if f.pr.MergeQueueEnabled {
		method, ask = "enqueue", hub.EnqueuePullRequest
	}
	if err := ask(f.pr.ID, ans.Head); err != nil {
		return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(fmt.Sprintf("the %s request at %s was refused "+
			"or not answered; the next run decides again: %v", method, ans.Head, err), c.note)}
	}
	return RunOutcome{Bead: s.id, Action: ActRequested, Detail: withNote(fmt.Sprintf("ready on the PR's re-read: the "+
		"%s is requested at %s into %s", method, ans.Head, ans.Target), c.note)}
}

// withNote is detail with the run's account of the record's withdrawals after
// it, when the run carried any out.
func withNote(detail, note string) string {
	if note == "" {
		return detail
	}
	return detail + "; " + note
}

// decideMerged decides a PR the saved read shows merged. A merge of the
// validated head is landed: the act fetches the target and closes the bead
// once the merge commit is on it. A merge of another head is an exception, and
// a recorded merge GitHub's facts contradict is another.
func (u *run) decideMerged(s state, p *gh.PullRequest) plan {
	r := s.rec
	if p.HeadRefOid != r.Head {
		return u.excepting(s, record.MergedUnvalidatedHead,
			fmt.Sprintf("Pull request %s merged a different head than refinery validated (%s -> %s).", r.URL, r.Head, p.HeadRefOid),
			fmt.Sprintf("Pull request %s merged at %s, a head the refinery did not validate (it validated %s), so %s "+
				"stays blocked, and what waits on it stays held. Check what merged into %s, then close %s as landed "+
				"or send the work back.", r.URL, p.HeadRefOid, r.Head, s.id, r.Target, s.id))
	}
	if !record.IsObjectID(p.MergeCommit) || p.MergedAt == "" {
		return none(s, ActRetry, "GitHub gives the PR merged without its merge commit and time; the next run decides again")
	}
	if r.Result == record.Merged && (p.MergeCommit != r.MergedSHA || p.MergedAt != r.MergedAt) {
		return u.contradiction(s, fmt.Sprintf("the recorded merge %s at %s is not GitHub's %s at %s", r.MergedSHA, r.MergedAt, p.MergeCommit, p.MergedAt))
	}
	return doing(func(ctx context.Context, _ carriedOut) RunOutcome { return u.land(ctx, s, p.MergeCommit, p.MergedAt) })
}

// land closes the bead once the merge commit is on a freshly fetched target,
// and keeps the merge it closed on for the seed audit's check. A merge whose
// commit the target does not reach yet is acted on again by the next run.
func (u *run) land(ctx context.Context, s state, commit, at string) RunOutcome {
	r := s.rec
	retry := func(why string) RunOutcome { return RunOutcome{Bead: s.id, Action: ActRetry, Detail: why} }
	if err := u.Checkout.FetchBranch(ctx, r.Target); err != nil {
		return retry(fmt.Sprintf("origin/%s did not fetch, so the merge is not verified; the next run acts again: %v", r.Target, err))
	}
	on, err := u.Checkout.Reaches(commit, r.Target)
	if err != nil || !on {
		if r.Result == record.Merged && err == nil {
			why := fmt.Sprintf("the recorded merge commit %s is no longer on origin/%s", commit, r.Target)
			return u.except(ctx, s, record.EvidenceContradiction, why, contradictionMessage(s, why))
		}
		why := fmt.Sprintf("PR merge commit %s is not reachable from origin/%s; the next run acts again", commit, r.Target)
		if err != nil {
			why = fmt.Sprintf("whether PR merge commit %s is on origin/%s did not read; the next run acts again: %v", commit, r.Target, err)
		}
		return retry(why)
	}
	number := r.Number
	landing := record.Landing{MergedSHA: commit, Target: r.Target, MergedAt: at}
	w := u.Ledger.Write(s.id)
	record.Land(w, landing, fmt.Sprintf("PR #%s merged to %s at %s (%s).", number, r.Target, short(commit), r.URL))
	w.Guard(s.status, s.assignee)
	err = u.Ledger.Commit(w)
	switch {
	case err == nil:
		u.landed = &landedMerge{bead: s.id, number: number, target: r.Target}
		return RunOutcome{Bead: s.id, Action: ActLanded,
			Detail: fmt.Sprintf("PR #%s merged to %s at %s: the bead is closed", number, r.Target, short(commit))}
	case errors.Is(err, ledger.ErrGuard):
		return RunOutcome{Bead: s.id, Action: ActMoved,
			Detail: "the bead moved since this run read it, so nothing landed: the merge at " + short(commit) + " is verified"}
	case closeRefused(err):
		return u.refused(ctx, s, landing, err)
	}
	// A write the store failed says nothing about the close, so the record
	// stands and the next run tries again.
	return retry("the merge is verified, but the close did not land; the next run acts again: " + err.Error())
}

// audit checks the seed audit on the rig's default branch once a PR has landed
// on it, and hands the pages stale there to the writer of the branch's
// re-render. It reads the branch at its tip as the act fetched it to verify the
// merge, so the check judges every merge on the branch, this one and any after
// it, and a tip already checked in this run is not checked again. It runs with
// the record lock free and holds nothing, whatever it finds: the bead has
// closed, and a check that does not run is asked for again at a later landing.
// It starts only inside the run's window. It returns the clause the landing's
// outcome carries, none for a landing on another branch or a rig whose
// repository carries no audit.
func (u *run) audit(m landedMerge, start time.Time, window time.Duration) string {
	if u.Audit == nil {
		return ""
	}
	def, err := u.Checkout.DefaultBranch()
	if err != nil {
		return "; the rig's default branch did not read, so no seed audit was checked, and a later landing checks it: " +
			err.Error()
	}
	if m.target != def {
		return ""
	}
	if window > 0 && u.clock().Sub(start) > window {
		return fmt.Sprintf("; the run had used its %s, so the seed audit on %s was not checked, and a later "+
			"landing checks it", window, def)
	}
	tip, err := u.Checkout.Tip(def)
	if err != nil {
		return fmt.Sprintf("; the tip of %s did not read, so its seed audit was not checked, and a later landing "+
			"checks it: %v", def, err)
	}
	if by, ok := u.audited[tip]; ok {
		return fmt.Sprintf("; the seed audit on %s at %s was checked after %s landed", def, short(tip), by)
	}
	pages, err := u.Audit.Stale(tip)
	if err != nil {
		return fmt.Sprintf("; the seed audit on %s at %s was not checked, and a later landing checks it: %v",
			def, short(tip), err)
	}
	if len(pages) == 0 {
		u.checked(tip, m.bead)
		return fmt.Sprintf("; the seed audit on %s is current at %s", def, short(tip))
	}
	stale := fmt.Sprintf("; the seed audit on %s at %s is stale in %d of its pages", def, short(tip), len(pages))
	seenBy := fmt.Sprintf("The landing order, checking %s at %s after PR #%s landed,", def, tip, m.number)
	answer, err := u.Audit.Reaudit(def, seenBy, pages)
	if err != nil {
		return stale + ", and its re-render was not asked for, so a later landing asks again: " + err.Error()
	}
	u.checked(tip, m.bead)
	return stale + ", and its re-render's writer answered " + answer
}

// checked keeps that the landing of bead checked the seed audit at tip.
func (u *run) checked(tip, bead string) {
	if u.audited == nil {
		u.audited = map[string]string{}
	}
	u.audited[tip] = bead
}

// closeRefused reports whether a write that closes a bead failed because bd
// refused the close itself, which it says as "cannot close ...": an open child
// or a live blocker (beads' close policy) holds it. Any other failure is the
// store's.
func closeRefused(err error) bool { return strings.Contains(err.Error(), "cannot close") }

// refused keeps a verified merge whose close bd refused blocked behind its
// gate, the exception CloseRefused, with the merge's evidence recorded: what
// holds the close is no fact the landing order can change, so a person
// resolves it.
func (u *run) refused(ctx context.Context, s state, l record.Landing, why error) RunOutcome {
	said := why.Error()
	if i := strings.Index(said, "cannot close"); i >= 0 {
		said = said[i:]
	}
	reason := fmt.Sprintf("Pull request %s merged to %s at %s, and the merge commit is on the target, but bd refused to close %s: %s",
		s.rec.URL, l.Target, short(l.MergedSHA), s.id, strings.Join(strings.Fields(said), " "))
	w := u.Ledger.Write(s.id)
	record.Refuse(w, l, reason)
	done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActExcepted, Detail: record.CloseRefused + ": " + reason})
	if done.Action != ActExcepted {
		return done
	}
	s.status = "blocked"
	return u.gate(ctx, s, record.CloseRefused, refusedMessage(s.id, reason), done)
}

// refusedMessage is the message of a CloseRefused gate: what merged, what bd
// refused, and how a person finishes the landing once what held the close is
// gone.
func refusedMessage(id, reason string) string {
	return fmt.Sprintf("%s. %s stays blocked, and what waits on it stays held. Close or stand down what holds it, then "+
		"clear this gate and close %s as landed: gc bd update %s --status=closed --set-metadata merge_result=%s. Its "+
		"record already carries the merge's evidence.", reason, id, id, id, record.Merged)
}

// invalid keeps a record that no longer reads as one blocked behind its gate.
func (u *run) invalid(s state, why string) plan {
	return u.excepting(s, record.Invalid, why,
		fmt.Sprintf("The pending record on %s no longer matches its pull request: %s. %s stays blocked, and what "+
			"waits on it stays held. Correct the record or the pull request, or stand the work down.", s.id, why, s.id))
}

// contradiction keeps a recorded merge GitHub's facts contradict blocked behind
// its gate.
func (u *run) contradiction(s state, why string) plan {
	return u.excepting(s, record.EvidenceContradiction, why, contradictionMessage(s, why))
}

// contradictionMessage is the message of an EvidenceContradiction gate.
func contradictionMessage(s state, why string) string {
	return fmt.Sprintf("GitHub's merge facts contradict the merge recorded on %s: %s. %s stays blocked, and what waits "+
		"on it stays held. Check what merged into %s before closing it.", s.id, why, s.id, firstOf(s.rec.Target, "the target"))
}

// excepting is the act that records an exception and files its gate (except).
func (u *run) excepting(s state, result, reason, message string) plan {
	return doing(func(ctx context.Context, _ carriedOut) RunOutcome { return u.except(ctx, s, result, reason, message) })
}

// except records the exception with the bead blocked, guarded on what the run
// read, then files the human gate keyed by it and clears the marker. A bead that
// moved since the read gets neither the record nor the gate.
func (u *run) except(ctx context.Context, s state, result, reason, message string) RunOutcome {
	w := u.Ledger.Write(s.id)
	record.Except(w, result, reason)
	done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActExcepted, Detail: result + ": " + reason})
	if done.Action != ActExcepted {
		return done
	}
	s.status = "blocked"
	return u.gate(ctx, s, result, message, done)
}

// gate files the exception's human gate on a bead the record already holds
// blocked, then clears the marker. A gate that does not file leaves the
// marker, and the exception the record holds, so the next run files it.
func (u *run) gate(ctx context.Context, s state, result, message string, done RunOutcome) RunOutcome {
	if err := u.Gates.File(ctx, s.id, result, message); err != nil {
		return RunOutcome{Bead: s.id, Action: ActRetry,
			Detail: fmt.Sprintf("%s: the human gate did not file; the next run files it: %v", result, err)}
	}
	w := u.Ledger.Write(s.id)
	record.Unmark(w)
	return u.commit(s, w, done)
}

// OriginError is a PR outside the rig's own repository, the one the clone's
// origin names.
type OriginError struct{ Why string }

func (e *OriginError) Error() string { return e.Why }

// sameOrigin refuses a PR outside the rig's own repository. An origin that
// does not read is a read that did not answer, not a refusal.
func (l Landing) sameOrigin(host, repo string) error {
	raw, err := l.Checkout.OriginURL()
	if err != nil {
		return fmt.Errorf("the rig's origin did not read: %w", err)
	}
	if why := outsideOrigin(raw, host, repo); why != "" {
		return &OriginError{Why: why}
	}
	return nil
}

// outsideOrigin says why a PR on host in repo is not in the repository the
// origin URL raw names, and is empty when it is.
func outsideOrigin(raw, host, repo string) string {
	oh, orepo, ok := originRepo(raw)
	if !ok {
		return fmt.Sprintf("the rig's origin %s names no repository on a host", raw)
	}
	if !strings.EqualFold(oh, host) || !strings.EqualFold(orepo, repo) {
		return fmt.Sprintf("the PR's repository %s/%s is not the rig's origin %s/%s", host, repo, oh, orepo)
	}
	return ""
}

// originForms are the forms a clone's origin URL takes: https, with or without
// credentials, scp-like ssh, and ssh.
var originForms = []*regexp.Regexp{
	regexp.MustCompile(`^https://(?:[^@/]+@)?([^/]+)/([^/]+/[^/]+?)(?:\.git)?/?$`),
	regexp.MustCompile(`^[^@/]+@([^:/]+):([^/]+/[^/]+?)(?:\.git)?/?$`),
	regexp.MustCompile(`^ssh://(?:[^@/]+@)?([^/:]+)(?::[0-9]+)?/([^/]+/[^/]+?)(?:\.git)?/?$`),
}

// originRepo reads an origin URL into its host and its repository, owner/name.
func originRepo(u string) (host, repo string, ok bool) {
	for _, f := range originForms {
		if m := f.FindStringSubmatch(strings.TrimSpace(u)); m != nil {
			return m[1], m[2], true
		}
	}
	return "", "", false
}

// mergeEvidence reports whether a recorded merge is whole: its commit and its
// time, which the landing writes. pr_state is the one-PR update's read of
// GitHub, not the landing's evidence.
func mergeEvidence(r record.Record) bool {
	return record.IsObjectID(r.MergedSHA) && r.MergedAt != ""
}

// nobody names an assignee, "nobody" for none.
func nobody(a string) string {
	if a == "" {
		return "nobody"
	}
	return a
}
