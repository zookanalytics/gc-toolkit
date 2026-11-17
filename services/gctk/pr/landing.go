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
// runs act on each record with Reconcile. A run decides every record from the
// store and the read the one-PR update (refresh.go) saved on its bead, and
// reads GitHub only for a merge, which it decides again on its own read of the
// PR and pins to the head it judged. It closes a bead once the merge commit is
// on the target, sends a changed head back to the refinery and sees that the
// refinery hears of it, keeps the exceptions blocked behind a human gate, marks
// a draft ready and carries out an approval's withdrawal, each from the saved
// read. A ruling that retires a PR records its disposition on the bead under
// the record lock and then closes the PR (pr-dispose.sh). A run requests no
// merge of a PR whose bead carries it, and once the saved read finds the PR
// closed the bead goes to the disposition writer, bead-rehome.sh, which closes
// it onto the successor the ruling named, with the lock free, while the bead
// still has the status and assignee the run judged and still records that
// ruling. A run saves none of what GitHub says: the one-PR update is the one
// writer of GitHub's side on a bead, the saved read, pr_state and
// pr_last_checked_at. Both take the store's record lock, Record across both of
// its writes and a run for one act at a time, and every write they make
// carries bd's guards on the status and the assignee
// read under the lock, so neither writes over a bead that a close or a release
// reached first. A run that lands a PR on the rig's default branch then checks
// that branch's seed audit with the lock free, and asks for the branch's
// re-render when the audit is stale, holding no PR for it (the design's call 1).

// Hub is GitHub as the landing order and the draft cycle reach it: the
// evaluator's reads, which the merge makes, a merge request or an enqueue
// pinned to the head it judged, the PR's moves between draft and ready, and the
// dismissal of a review.
type Hub interface {
	GitHub
	MergePullRequest(id, head string) error
	EnqueuePullRequest(id, head string) error
	MarkReady(id string) error
	ConvertToDraft(id string) error
	DismissReview(repo string, number int, id int64, message string) error
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

// Gates files a human gate on a bead under a key, or finds the one open there.
type Gates interface {
	File(subject, key, message string) error
}

// Waker wakes a session and nudges it with a message, so a session that is
// asleep starts and one that is up gets a turn, as a polecat's hand-off to the
// refinery does (work-submit.sh). An error says which of the two did not land.
type Waker interface {
	Wake(session, message string) error
}

// Dispositions is the writer of a close that is not a landing, bead-rehome.sh,
// as the landing order reaches it for a bead whose PR a ruling retired. Close
// closes the bead x names onto the successor its ruling named, under its kind,
// with its note beside the close, acting as the refinery the bead is assigned
// to. The writer takes the store's record lock itself, from its read of the
// bead to its close, so the order calls it with the lock free, and it closes
// the bead only while the bead still has the status and assignee the run
// judged it under and still records the ruling the run read. A close the writer
// holds for now, because a wait on the bead is still open or the bead moved
// since the run judged it or since the writer read it, is a *HeldClose.
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
// a release or a second ruling. The next run reads the bead again.
type HeldClose struct{ Why string }

func (e *HeldClose) Error() string { return e.Why }

// Landing is what the record's verbs act through. Dir is the store's .beads
// directory, where the record lock lives, and Refinery the assignee of a bead
// the refinery holds, which is also the session Wake wakes. Hub is GitHub on a
// host, each call stopped when ctx ends. Feedback loads the definition of
// feedback, once a run first needs it. Mark reads the city's mark, which a
// dismissal's message carries, from the writer that owns it. Runs pours a PR's
// review run, and Dispositions closes a bead whose PR a ruling retired. Audit
// is the rig's seed audit, nil for a rig whose repository carries none. Wake
// gives the refinery a turn for a changed head that only conversations and asks
// hold. Labels keeps the labels of each PR the store's live beads own equal to
// the ones the store derives, and a run writes none when it is nil. Wait bounds
// how long a writer waits for the lock, and Yield is how long a run lets the
// lock stand free between two acts, so a writer waiting for it takes it.
// Shuffle orders the acts a run takes, at random when nil. Now is the clock a
// write's stamp and a run's window read, the system's when nil.
type Landing struct {
	Ledger       *ledger.Ledger
	Dir          string
	Refinery     string
	Hub          func(ctx context.Context, host string) Hub
	Feedback     func() (Feedback, error)
	Mark         func() (string, error)
	Checkout     Checkout
	Gates        Gates
	Runs         Runs
	Dispositions Dispositions
	Audit        Audit
	Wake         Waker
	Labels       Labels
	Now          func() time.Time
	Wait         time.Duration
	Yield        time.Duration
	Shuffle      func([]string)
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
// may reuse, then the whole record with the bead blocked. It reads the bead
// under the lock first, and writes only on a bead that is not closed and is
// assigned to the refinery, each write guarded on the status and assignee it
// read. A bead it refuses returns a *Refusal. The PR must be in the rig's own
// repository, which Record checks before it takes the lock.
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
			return &Refusal{Bead: bead, Why: "it was closed or released after this publication read it"}
		}
		return err
	}
	publish := l.Ledger.Write(bead)
	publish.Guard(status, assignee)
	record.Publish(publish, p)
	if err := l.Ledger.Commit(publish); err != nil {
		if errors.Is(err, ledger.ErrGuard) {
			return &Refusal{Bead: bead, Armed: true, Why: "it was closed or released between the publication's two writes"}
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
	// the PR stands as the record says, a read the decision rests on, such as
	// the saved read, is not there yet, and the PR watch saves it, or the
	// disposition writer holds a retired PR's close for now, and the next run
	// hands it over again.
	ActChecked = "checked"
	// ActRequested: the evaluator found the PR ready on the merge's own read of
	// GitHub, and the run asked GitHub to merge it, or to add it to its base's
	// merge queue, at the head it judged.
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
	// ActRequeued: the PR is open at another head, and the bead went back to the
	// refinery.
	ActRequeued = "requeued"
	// ActRevalidate: the record was half written, and the bead went back to the
	// refinery for its full validation.
	ActRevalidate = "revalidate"
	// ActExcepted: an exception, filed as a human gate, keeps the bead blocked.
	ActExcepted = "excepted"
	// ActRetry: the record's act did not complete, or the run could not decide
	// it: a call GitHub refused or did not answer, a fetch, a read, a filing or
	// a label write that failed, or an act stopped at its bound. Nothing records
	// it, the difference stays on the bead, and the next run acts on it again.
	ActRetry = "retry"
	// ActLabeled: the status: and held: labels the PR shows differ from the
	// ones the store derives, and the run had the labels' writer write them:
	// the derived labels on an open PR, and none on one that merged or closed.
	ActLabeled = "labeled"
	// ActReleased: a release took the bead from the refinery, and the run cleared
	// the marker and named the PR in a note.
	ActReleased = "released"
	// ActSettled: no further run is owed, and the run cleared the marker.
	ActSettled = "settled"
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
	// so the next run acts on it.
	ActLeft = "left"
	// ActFailed: a write or a read of the store failed in a way the next run may
	// not clear.
	ActFailed = "failed"
)

// Options bound one run: Window is how long into the run it starts another
// act, and Stop how long one act runs before it is stopped, with whatever
// GitHub call or fetch it is making. A bound of zero is no bound.
type Options struct {
	Window time.Duration
	Stop   time.Duration
}

// Reconcile is one run of the landing order. It reads the store once, through
// a ledger pass that lists the beads that carry the marker, closed ones too,
// and every live bead, and decides each record that carries the marker, and
// each bead on the record that carries a ruling's disposition (disposing), from
// the store and the read saved on its bead. A record that owes no act reports
// what it waits on. With Labels set, each PR the live beads own whose saved
// labels differ from the ones the store derives owes a label write too
// (labelPlans). The records and the PRs that owe an act are taken in a
// shuffled order, so one whose act is slow or keeps failing holds no other
// back, and none is started past o.Window. Each record's act reads its record
// again under the record lock, decides again from that read, and acts within
// o.Stop, its writes guarded on the status and assignee it read there. A label
// write takes no lock and writes nothing on the bead, and stops at o.Stop too.
// A bead whose PR closed under a ruling's disposition goes to the disposition
// writer once the lock is released (dispose). A record that lands on the rig's
// default branch has the branch's seed audit checked once the lock is
// released, inside the window, and its outcome says what the check found. It
// reports each outcome to report as it goes, and returns an error when the
// listing did not answer, or when a record or a PR's labels could not be
// decided or its act did not complete.
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
	for _, p := range plans {
		switch {
		case p.write != nil:
			writes[p.id] = *p.write
		case p.act == nil:
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
		u.landed, u.disposal = nil, nil
		out := u.one(id, o.Stop)
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
// blocked, is the refinery's and carries a whole disposition. rec is r's
// record.
func (l Landing) disposing(r *ledger.Record, rec record.Record) bool {
	if !record.OnRecord(rec.Result) || r.Assignee() != l.Refinery {
		return false
	}
	if s := r.Status(); s != "open" && s != "blocked" {
		return false
	}
	_, whole, err := dispositionOf(r)
	return err == nil && whole
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
// owes the disposition writer once the lock is free, and audited names, for
// each tip of the default branch the run has checked, the bead whose landing
// checked it.
type run struct {
	Landing
	feedback Feedback
	mark     string
	origin   *string
	logins   map[string]string
	contains map[[2]string]bool
	fetched  map[string]bool
	landed   *landedMerge
	disposal *Disposal
	audited  map[string]string
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

// readHub is GitHub as the evaluator reads it on the merge's own read: the hub
// of the record's host, which answers the PR the act read just before it with
// that read and the login with the run's own, so the evaluator reads neither
// again. Its other reads go to GitHub.
type readHub struct {
	Hub
	pr    *gh.PullRequest
	login func() (string, error)
}

func (h readHub) PullRequest(repo string, number int) (*gh.PullRequest, error) {
	if h.pr != nil && number == h.pr.Number && strings.EqualFold(repo, h.pr.Repository) {
		return h.pr, nil
	}
	return h.Hub.PullRequest(repo, number)
}

func (h readHub) Login() (string, error) { return h.login() }

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
// A PR whose labels owe a write is planned under its URL, and write holds the
// write.
type plan struct {
	id    string
	out   RunOutcome
	act   act
	write *labelWrite
}

func none(s state, action, detail string) plan {
	return plan{out: RunOutcome{Bead: s.id, Action: action, Detail: detail}}
}

func doing(a act) plan { return plan{act: a} }

// plan reads the store once, through a pass that lists the beads that carry
// the marker, closed ones too, and then, when there is one or the run keeps
// the PRs' labels, every live bead, so each question the decisions ask answers
// from those rows. The live beads that carry a ruling's disposition answer
// from those rows too, and from a read of their own when the pass holds no
// live bead. It decides each marked record that is open, blocked or closed,
// and each bead it reads for its disposition (disposing), and a record it
// could not decide owes an act, whose read under the lock decides it. A record
// that does not read as a record is not one the run can act on. With Labels
// set, the label writes the owned PRs owe follow (labelPlans). The plans are
// in id order.
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
			return nil, nil
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
		case "open", "blocked", "closed":
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
	var out []plan
	for _, r := range due {
		p := u.decideRow(pass, r)
		p.id = r.ID
		if p.act == nil && p.out.Bead == "" {
			p.out.Bead = r.ID
		}
		if p.act == nil && (p.out.Action == ActRetry || p.out.Action == ActFailed) {
			// The listing's reads run with no lock, so another writer's write can
			// land between two of them. A record they could not decide is decided
			// again under the lock, from reads no writer of the record moves.
			p.act = func(context.Context, carriedOut) RunOutcome { return p.out }
		}
		out = append(out, p)
	}
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

// decideRow reads the record r carries through l and decides it.
func (u *run) decideRow(l *ledger.Ledger, r *ledger.Record) plan {
	s, stop := u.state(l, r)
	if stop != nil {
		return plan{out: *stop}
	}
	return u.decide(s)
}

// state reads the record r carries, through l: its record, the disposition a
// ruling recorded on it, its branch and provenance instant, and for a bead the
// refinery holds open or blocked, what its blocks edges name. A bead whose
// record no longer carries the marker, unless a run reads it for its
// disposition (disposing), or whose parts do not read, gets the outcome that
// says so in place of a state.
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
	if (s.status != "open" && s.status != "blocked") || s.assignee != u.Refinery {
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
// decides again from that read, and makes the act it owes, stopped at stop.
// A lock that does not come free inside the act's bound is an act that did not
// complete.
func (u *run) one(id string, stop time.Duration) RunOutcome {
	ctx, cancel := context.Background(), context.CancelFunc(func() {})
	if stop > 0 {
		ctx, cancel = context.WithTimeout(ctx, stop)
	}
	defer cancel()
	wait := u.Wait
	if stop > 0 && (wait <= 0 || stop < wait) {
		wait = stop
	}
	release, err := record.Lock(u.Dir, wait)
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
	p := u.decideRow(u.Ledger.Pass(), r)
	if p.act == nil {
		if p.out.Bead == "" {
			p.out.Bead = id
		}
		return p.out
	}
	out := p.act(ctx, carriedOut{})
	if ctx.Err() != nil && out.Action == ActRetry {
		out.Detail = fmt.Sprintf("the act was stopped at its %s: %s", stop, out.Detail)
	}
	return out
}

// decide is what the record s read owes.
func (u *run) decide(s state) plan {
	switch {
	case s.status == "closed":
		return u.decideClosed(s)
	case s.assignee != u.Refinery:
		return doing(func(context.Context, carriedOut) RunOutcome { return u.released(s) })
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

// released clears the marker of a bead a release took from the refinery, and
// names the PR in a note, writing nothing else, so the bead stays where the
// release left it.
func (u *run) released(s state) RunOutcome {
	pr := firstOf(s.rec.URL, s.rec.ExistingPR, "the pull request it recorded")
	note := fmt.Sprintf("The landing order found %s %s and assigned to %s, not to the refinery, while it carried "+
		"the pending record of %s, so it cleared the record's marker and left the bead as it stands (%s).",
		s.id, s.status, nobody(s.assignee), pr, s.now)
	w := u.Ledger.Write(s.id)
	record.Unmark(w, note)
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActReleased,
		Detail: fmt.Sprintf("assigned to %s, not to the refinery: the marker is cleared and %s is named in a note", nobody(s.assignee), pr)})
}

// decideClosed decides a closed bead that still carries the marker. One closed
// on a verified merge owes nothing more, and its marker clears. Any other is a
// close that took no lock and reached the bead with no verified merge, which a
// run reopens as blocked, behind a gate.
func (u *run) decideClosed(s state) plan {
	if s.rec.Result == record.Merged && mergeEvidence(s.rec) {
		return doing(func(context.Context, carriedOut) RunOutcome {
			w := u.Ledger.Write(s.id)
			record.Unmark(w, "")
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

// decideOpen decides an open bead the refinery holds. A changed head is held
// from the refinery while a withdrawal is open on the bead, which the run
// carries out, or while a review run is attached to it, whose end a later run
// reads, and the marker stays until then. Once neither holds it, the run hands
// it to the refinery (handOver). A whole record whose second write landed moves
// to blocked and is decided on. Anything else is a record a dead writer left
// half written, which goes back to the refinery for its full validation.
func (u *run) decideOpen(s state) plan {
	switch {
	case s.rec.Result == record.HeadChanged && withdrawing(s):
		return u.decideRequeued(s)
	case s.rec.Result == record.HeadChanged && len(s.runs) > 0:
		return none(s, ActChecked, onRuns(s))
	case s.rec.Result == record.HeadChanged:
		return doing(func(context.Context, carriedOut) RunOutcome {
			return u.handOver(s, ActSettled, "its changed head waits on the refinery's validation")
		})
	case s.rec.Result == record.Pending && len(recordGaps(s.rec, s.branch)) == 0:
		return doing(func(ctx context.Context, c carriedOut) RunOutcome {
			w := u.Ledger.Write(s.id)
			record.Block(w)
			done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActBlocked, Detail: "the whole record had landed on an open bead"})
			if done.Action != ActBlocked {
				return done
			}
			s.status = "blocked"
			next := u.decideBlocked(s)
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
		record.Revalidate(w, "Interrupted PR handoff record is incomplete; full refinery validation is required")
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRevalidate,
			Detail: "the record was half written: the bead goes back to the refinery, and no merge is requested"})
	})
}

// withdrawing reports whether a withdrawal is open on the record s read.
func withdrawing(s state) bool {
	return slices.ContainsFunc(s.withdrawals, func(w withdrawal) bool { return w.open })
}

// savedPR is the read the one-PR update saved on the record's bead, and why it
// is no read of the record's PR when it is not: none saved, none of the PR's
// own facts, or a read of another PR. The PR watch reads a bead's PR afresh
// whenever its saved read is not current for the bead.
func savedPR(s state, number int) (*SavedRead, string) {
	saved, _, err := githubReadKey.Get(s.row)
	switch {
	case err != nil:
		return nil, "the saved read does not decode, and the PR watch saves it afresh: " + err.Error()
	case saved == nil || saved.PR == nil:
		return nil, "no read of the PR itself is saved on the bead, and the PR watch saves one"
	case !strings.EqualFold(saved.PR.Repository, s.rec.Repo) || saved.PR.Number != number:
		return nil, fmt.Sprintf("the saved read is of %s#%d, and the PR watch reads the bead's own PR", saved.PR.Repository, saved.PR.Number)
	}
	return saved, ""
}

// identity names where the saved PR differs from the one the record names, as
// identityGaps compares a PR GitHub reports.
func identity(p *SavedPR, s state, number int) []string {
	named := &gh.PullRequest{URL: p.URL, Number: p.Number, Repository: p.Repository, HeadRefName: p.HeadBranch,
		BaseRefName: p.Base}
	return identityGaps(named, s.rec.URL, number, s.rec.Repo, s.branch, s.rec.Target)
}

// decideRequeued decides a changed head the run sent back to the refinery while
// a withdrawal is open on it, from the saved read. It carries the withdrawal
// out while the PR is open, keeping the marker while a withdrawal is open or a
// review run is attached, so the bead goes to the refinery once nothing the
// order owes holds it (handOver). A PR that closed or merged meanwhile is the
// record's exception, as on a pending record.
func (u *run) decideRequeued(s state) plan {
	r := s.rec
	if missing := recordGaps(r, s.branch); len(missing) > 0 {
		return u.invalid(s, "the requeued record is incomplete: it lacks "+strings.Join(missing, ", "))
	}
	host, _, number, _ := record.ParseURL(r.URL)
	saved, why := savedPR(s, number)
	if why != "" {
		return none(s, ActChecked, "its changed head waits on the refinery, behind the withdrawal, and "+why)
	}
	if why := u.originDiffers(host, r.Repo); why != "" {
		return none(s, ActRetry, why+"; the next run decides again")
	}
	if ids := identity(saved.PR, s, number); len(ids) > 0 {
		return u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
	}
	switch saved.PR.State {
	case "OPEN":
		if note, acts, failed := u.carrying(s, saved); !acts {
			action := ActChecked
			if failed {
				action = ActRetry
			}
			return none(s, action, "its changed head waits on the refinery, behind the withdrawal: "+note)
		}
		return u.withCarry(s, saved, doing(func(_ context.Context, c carriedOut) RunOutcome {
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
			return u.handOver(s, ActSettled, withNote("its changed head waits on the refinery's validation", c.note))
		}))
	case "CLOSED":
		return u.excepting(s, record.ClosedUnmerged, "Pull request "+r.URL+" closed without merging.",
			fmt.Sprintf("Pull request %s closed without merging while a withdrawal of its approvals was open, so %s stays "+
				"blocked, and what waits on it stays held. Decide what becomes of the work: reopen the pull request and "+
				"send %s back to the refinery, or stand the work down.", r.URL, s.id, s.id))
	case "MERGED":
		return u.decideMerged(s, saved.PR)
	}
	return none(s, ActRetry, fmt.Sprintf("the saved read gives the PR's state as %q, which is no state the record knows; the next run decides again", saved.PR.State))
}

// decideBlocked decides a blocked bead the refinery holds: the record must be
// whole and must read pending, or a verified merge whose close did not land.
// Its PR is decided from the saved read.
func (u *run) decideBlocked(s state) plan {
	r := s.rec
	if record.Exception(r.Result) {
		// A run recorded the exception and stopped before its gate filed.
		message := fmt.Sprintf("%s %s stays blocked, and what waits on it stays held, until a person "+
			"decides what becomes of the work.", firstOf(r.BlockedReason, "The pending record met "+r.Result+"."), s.id)
		if r.Result == record.CloseRefused {
			message = refusedMessage(s.id, firstOf(r.BlockedReason, "A verified merge's close was refused"))
		}
		return doing(func(context.Context, carriedOut) RunOutcome {
			return u.gate(s, r.Result, message,
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
	host, _, number, _ := record.ParseURL(r.URL)
	saved, why := savedPR(s, number)
	if why != "" {
		return none(s, ActChecked, "the record waits for the PR watch: "+why)
	}
	if why := u.originDiffers(host, r.Repo); why != "" {
		return none(s, ActRetry, why+"; the next run decides again")
	}
	p := saved.PR
	if ids := identity(p, s, number); len(ids) > 0 {
		return u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
	}
	if !record.IsObjectID(p.Head) {
		return u.invalid(s, fmt.Sprintf("GitHub names the PR's head %q, which is no commit id", p.Head))
	}
	switch p.State {
	case "OPEN":
		if r.Result == record.Merged {
			return u.contradiction(s, fmt.Sprintf("%s recorded a merge at %s, and GitHub reports the PR open", s.id, r.MergedSHA))
		}
		if p.Head != r.Head {
			return u.decideHeadChanged(s, saved)
		}
		return u.decideAtHead(s, saved)
	case "CLOSED":
		return u.excepting(s, record.ClosedUnmerged, "Pull request "+r.URL+" closed without merging.",
			fmt.Sprintf("Pull request %s closed without merging, so %s stays blocked, and what waits on it stays "+
				"held. Decide what becomes of the work: reopen the pull request and send %s back to the refinery, "+
				"or stand the work down.", r.URL, s.id, s.id))
	case "MERGED":
		return u.decideMerged(s, p)
	}
	return none(s, ActRetry, fmt.Sprintf("the saved read gives the PR's state as %q, which is no state the record knows; the next run decides again", p.State))
}

// decideDisposed decides a bead on the record that carries the disposition a
// ruling recorded before it closed the PR (pr-dispose.sh), from the saved read.
// The PR will not land, so the run requests no merge, pours no review run,
// marks nothing ready and carries out no withdrawal, whatever the saved read
// says of it. One still open waits for its close, one that merged all the same
// lands as any merge does, and one that has closed is retired (decideRetired).
func (u *run) decideDisposed(s state) plan {
	r := s.rec
	if missing := recordGaps(r, s.branch); len(missing) > 0 {
		return u.invalid(s, "the record is incomplete: it lacks "+strings.Join(missing, ", "))
	}
	host, _, number, _ := record.ParseURL(r.URL)
	saved, why := savedPR(s, number)
	if why != "" {
		return none(s, ActChecked, s.disposition.ruling()+", and the record waits for the PR watch: "+why)
	}
	if why := u.originDiffers(host, r.Repo); why != "" {
		return none(s, ActRetry, why+"; the next run decides again")
	}
	if ids := identity(saved.PR, s, number); len(ids) > 0 {
		return u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
	}
	switch saved.PR.State {
	case "OPEN":
		return none(s, ActChecked, s.disposition.ruling()+", so no merge is requested, and the PR's close finishes it")
	case "CLOSED":
		return u.decideRetired(s, number)
	case "MERGED":
		return u.decideMerged(s, saved.PR)
	}
	return none(s, ActRetry, fmt.Sprintf("the saved read gives the PR's state as %q, which is no state the record knows; the next run decides again", saved.PR.State))
}

// decideRetired decides a PR a ruling retired once the saved read finds it
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
// on the bead holds, or the close of a bead released or ruled again since the
// act judged it, waits for the next run, which reads the bead again under the
// lock, so it reports as checked.
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

// decideHeadChanged decides a PR the saved read finds open at a head other than
// the one the refinery validated. A saved head the validated one descends from
// is a read made before the refinery pushed and recorded that head, which the
// PR watch reads again, since the read is not current for the bead: nothing is
// sent back on it, and the record's withdrawals are carried out alone. Any
// other head goes back to the refinery, after the withdrawals, keeping the
// marker while one is still open or a review run is attached, and until the
// hand-over has woken a refinery that nothing else tells of the head
// (handOver).
func (u *run) decideHeadChanged(s state, saved *SavedRead) plan {
	r, seen := s.rec, saved.PR.Head
	older, err := u.holds(r.Head, seen)
	if err != nil {
		return none(s, ActRetry, fmt.Sprintf("whether the validated head %s descends from %s, the head the saved read "+
			"found, did not read, so nothing is sent back; the next run decides again: %v", r.Head, seen, err))
	}
	if older {
		return u.withCarry(s, saved, none(s, ActChecked, fmt.Sprintf("the saved read is at %s, a head the validated %s "+
			"descends from, so it was read before the refinery recorded its head, and the PR watch reads the PR again "+
			"before anything is sent back", seen, r.Head)))
	}
	return u.withCarry(s, saved, doing(func(_ context.Context, c carriedOut) RunOutcome {
		reason := fmt.Sprintf("PR head changed after refinery validation (%s -> %s); quality gates must run again", r.Head, seen)
		detail := withNote(reason, c.note)
		if !c.held && len(s.runs) > 0 {
			detail = withNote(reason+"; "+onRuns(s), c.note)
		}
		// The requeue keeps the marker while a withdrawal or an attached run
		// holds the changed head, and for the hand-over that wakes the
		// refinery once the requeue lands, or that reads what holds the bead
		// again when this read fails.
		watched := c.held || len(s.runs) > 0
		var holds []hold
		var unread error
		if !watched {
			holds, unread = u.mergeHolds(s)
		}
		keep := watched || unread != nil || len(holds) > 0
		w := u.Ledger.Write(s.id)
		record.Requeue(w, r.URL, seen, reason, keep)
		done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRequeued, Detail: detail})
		if done.Action != ActRequeued || !keep || watched {
			return done
		}
		s.status = "open"
		if unread != nil {
			return u.handOverLater(s, detail, "what holds the bead did not read, so the next run reads it again: "+unread.Error())
		}
		return u.wakeAndSettle(s, holds, ActRequeued, detail)
	}))
}

// decideAtHead decides a PR the saved read finds open at the validated head. A
// PR already in its base's merge queue owes nothing. A draft the review loop
// has passed at its head, with no review run attached and no ask a run can
// take, is marked ready, and the next run decides it again (readyBar).
// Otherwise the evaluator decides over the saved read whether the PR is ready.
// One it finds not ready is owed a review run when it has no passed result at
// the head or an ask a run can take is open, which the run pours (admit). One it
// finds ready is merged on the merge's own read.
func (u *run) decideAtHead(s state, saved *SavedRead) plan {
	p := saved.PR
	if p.InMergeQueue {
		return u.withCarry(s, saved, none(s, ActChecked, "the PR is in its base's merge queue, which holds its merge request"))
	}
	asks, err := review.AsksIn(s.reads, s.row, s.blockers)
	if err != nil {
		return none(s, ActRetry, "the asks on the bead did not read; the next run decides again: "+err.Error())
	}
	if p.Draft {
		results, _, err := review.Results.Get(s.row)
		if err != nil {
			return none(s, ActRetry, "the review results did not read; the next run decides again: "+err.Error())
		}
		if readyBar(s, p, results, asks) == "" {
			return u.withCarry(s, saved, doing(func(ctx context.Context, c carriedOut) RunOutcome {
				host, _, _, _ := record.ParseURL(s.rec.URL)
				if err := u.Hub(ctx, host).MarkReady(p.ID); err != nil {
					return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(fmt.Sprintf("the ready transition at %s "+
						"was refused or not answered, and the next run decides again from the draft flag the PR watch "+
						"saves: %v", p.Head, err), c.note)}
				}
				return RunOutcome{Bead: s.id, Action: ActReadied, Detail: withNote(fmt.Sprintf("marked ready at %s, without "+
					"waiting for CI: a passed result names the head, and no review run is attached and no ask a run can "+
					"take is open; the next run decides again", p.Head), c.note)}
			}))
		}
	}
	ans, err := FromStore(s.reads, s.id)
	if err != nil {
		return none(s, ActRetry, "the evaluator's read of the store did not answer; the next run decides again: "+err.Error())
	}
	if !ans.Ready {
		if owed, ok := u.admit(s, ans, asks); ok {
			return u.withCarry(s, saved, owed)
		}
		var not []string
		for _, c := range ans.Conditions {
			not = append(not, string(c.Kind))
		}
		return u.withCarry(s, saved, none(s, ActChecked, "not ready: "+strings.Join(slices.Compact(not), ", ")))
	}
	return u.withCarry(s, saved, doing(func(ctx context.Context, c carriedOut) RunOutcome { return u.merge(ctx, s, c) }))
}

// merge decides the merge again on its own read of GitHub, made in this act,
// and asks GitHub to merge a PR that read finds ready, pinned to the head the
// answer judged, or to add it to its base's merge queue where the base
// requires one. A PR already in the queue has its merge requested. The
// evaluator reads the PR as the act read it a moment before, and the run's
// login (readHub). Whatever GitHub answers, the next run decides the PR again
// from the read the PR watch saves next.
func (u *run) merge(ctx context.Context, s state, c carriedOut) RunOutcome {
	retry := func(why string) RunOutcome {
		return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(why, c.note)}
	}
	host, _, number, _ := record.ParseURL(s.rec.URL)
	hub := u.Hub(ctx, host)
	p, err := hub.PullRequest(s.rec.Repo, number)
	if err != nil {
		return retry("the merge's own read of the PR did not answer, so no merge was requested; the next run decides again: " + err.Error())
	}
	if p.InMergeQueue {
		return RunOutcome{Bead: s.id, Action: ActChecked,
			Detail: withNote("the PR is in its base's merge queue, which holds its merge request", c.note)}
	}
	rule, err := u.rule()
	if err != nil {
		return retry("the definition of feedback did not load, so no merge was requested; the next run decides again: " + err.Error())
	}
	read := readHub{Hub: hub, pr: p, login: func() (string, error) { return u.login(host, hub) }}
	ans, _, err := Ready(Sources{Ledger: u.Ledger, GitHub: func(h string) GitHub {
		if h == host {
			return read
		}
		return u.Hub(ctx, h)
	}, Feedback: rule, Now: u.Now}, s.id)
	if err != nil {
		return retry("the merge's own read did not answer, so no merge was requested; the next run decides again: " + err.Error())
	}
	if !ans.Ready {
		var not []string
		for _, c := range ans.Conditions {
			not = append(not, string(c.Kind))
		}
		return RunOutcome{Bead: s.id, Action: ActChecked, Detail: withNote("the saved read found the PR ready, and the "+
			"merge's own read found it not ready, so no merge was requested: "+strings.Join(slices.Compact(not), ", "), c.note)}
	}
	// The merge request is the one act no guard can take back, so the bead is
	// read once more just before it: a close or a release that took no lock and
	// landed during the act's reads stops it here. One that lands after this
	// read is the residual the design names, a merge requested before the run
	// could read the release. A ruling's disposition takes the record lock, so
	// none lands while the act holds it: one recorded before the act read the
	// bead under the lock took the act to decideDisposed, and one that comes
	// later waits for the lock and lands after the request.
	now, err := u.read(s.id)
	if err != nil {
		return retry("the bead did not read again before the merge request; the next run decides again: " + err.Error())
	}
	if now == nil || now.Status() != s.status || now.Assignee() != s.assignee {
		return RunOutcome{Bead: s.id, Action: ActMoved, Detail: withNote(
			"the bead moved during the act's reads, so no merge was requested; the next run reads it as it stands", c.note)}
	}
	method, ask := "merge", hub.MergePullRequest
	if p.MergeQueueEnabled {
		method, ask = "enqueue", hub.EnqueuePullRequest
	}
	if err := ask(p.ID, ans.Head); err != nil {
		return retry(fmt.Sprintf("the %s request at %s was refused or not answered; the next run decides again: %v", method, ans.Head, err))
	}
	return RunOutcome{Bead: s.id, Action: ActRequested,
		Detail: withNote(fmt.Sprintf("ready: the %s is requested at %s into %s", method, ans.Head, ans.Target), c.note)}
}

// withNote is detail with the run's account of the record's withdrawals after
// it, when the run carried any out.
func withNote(detail, note string) string {
	if note == "" {
		return detail
	}
	return detail + "; " + note
}

// decideMerged decides a PR the saved read finds merged. A merge of the
// validated head is landed: the act fetches the target and closes the bead
// once the merge commit is on it. A merge of another head is an exception, and
// a recorded merge GitHub's facts contradict is another.
func (u *run) decideMerged(s state, p *SavedPR) plan {
	r := s.rec
	if p.Head != r.Head {
		return u.excepting(s, record.MergedUnvalidatedHead,
			fmt.Sprintf("Pull request %s merged a different head than refinery validated (%s -> %s).", r.URL, r.Head, p.Head),
			fmt.Sprintf("Pull request %s merged at %s, a head the refinery did not validate (it validated %s), so %s "+
				"stays blocked, and what waits on it stays held. Check what merged into %s, then close %s as landed "+
				"or send the work back.", r.URL, p.Head, r.Head, s.id, r.Target, s.id))
	}
	if !record.IsObjectID(p.MergeCommit) || p.MergedAt == "" {
		return none(s, ActRetry, "the saved read gives the PR merged without its merge commit and time; the next run decides again")
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
			return u.except(s, record.EvidenceContradiction, why, contradictionMessage(s, why))
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
		return u.refused(s, landing, err)
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
func (u *run) refused(s state, l record.Landing, why error) RunOutcome {
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
	return u.gate(s, record.CloseRefused, refusedMessage(s.id, reason), done)
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
	return doing(func(context.Context, carriedOut) RunOutcome { return u.except(s, result, reason, message) })
}

// except records the exception with the bead blocked, guarded on what the run
// read, then files the human gate keyed by it and clears the marker. A bead that
// moved since the read gets neither the record nor the gate.
func (u *run) except(s state, result, reason, message string) RunOutcome {
	w := u.Ledger.Write(s.id)
	record.Except(w, result, reason)
	done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActExcepted, Detail: result + ": " + reason})
	if done.Action != ActExcepted {
		return done
	}
	s.status = "blocked"
	return u.gate(s, result, message, done)
}

// gate files the exception's human gate on a bead the record already holds
// blocked, then clears the marker. A gate that does not file leaves the
// marker, and the exception the record holds, so the next run files it.
func (u *run) gate(s state, result, message string, done RunOutcome) RunOutcome {
	if err := u.Gates.File(s.id, result, message); err != nil {
		return RunOutcome{Bead: s.id, Action: ActRetry,
			Detail: fmt.Sprintf("%s: the human gate did not file; the next run files it: %v", result, err)}
	}
	w := u.Ledger.Write(s.id)
	record.Unmark(w, "")
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
