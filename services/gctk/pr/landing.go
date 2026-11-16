package pr

import (
	"errors"
	"fmt"
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
// sections 4 and 6). The refinery publishes a PR's pending record with Record,
// and the landing order's runs read each record with Reconcile: they request
// the merge of a PR the evaluator finds ready, close the bead once the merge
// commit is on the target, send a changed head back to the refinery, and keep
// the exceptions blocked behind a human gate. A ruling that retires a PR
// records its disposition on the bead under the record lock and then closes
// the PR (pr-dispose.sh). A run requests no merge of a PR whose bead carries
// it, and once the PR has closed the bead goes to the disposition writer,
// bead-rehome.sh, which closes it onto the successor the ruling named, with
// the lock free. Each check of an open PR saves
// GitHub's side of it on the bead, whole, in the write that records the check
// (specs/tk-1tfzr71.134/design.md, section 3), and nothing the run acts on
// reads that saved read back. Both take the store's record
// lock, Record across both of its writes and a run for one record at a time,
// and every write they make carries bd's guards on the status and the assignee
// read under the lock, so neither writes over a bead that a close or a release
// reached first. A run that lands a PR on the rig's default branch then checks
// that branch's seed audit with the lock free, and asks for the branch's
// re-render when the audit is stale, holding no PR for it (the design's call 1).

// Hub is GitHub as the landing order and the draft cycle reach it: the
// evaluator's reads, a merge request or an enqueue pinned to the head it
// judged, the PR's moves between draft and ready, the compare that says whether
// an approved commit contains a head, and the dismissal of a review.
type Hub interface {
	GitHub
	MergePullRequest(id, head string) error
	EnqueuePullRequest(id, head string) error
	MarkReady(id string) error
	ConvertToDraft(id string) error
	Compare(repo, base, head string) (string, error)
	DismissReview(repo string, number int, id int64, message string) error
}

// Checkout is the rig's clone, as the record reads it: its origin, the target
// it fetches, whether a merge commit is on the target fetched, its default
// branch, and a branch's tip as it was last fetched.
type Checkout interface {
	OriginURL() (string, error)
	FetchBranch(branch string) error
	Reaches(commit, branch string) (bool, error)
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

// Dispositions is the writer of a close that is not a landing, bead-rehome.sh,
// as the landing order reaches it for a bead whose PR a ruling retired. Close
// closes the bead onto the successor the ruling named, under its kind, with
// note beside the close, acting as the refinery the bead is assigned to. The
// writer takes the store's record lock itself, from its read of the bead to its
// close, so the order calls it with the lock free. A close the writer holds for
// now, because a wait on the bead is still open or the bead moved since its
// read, is a *HeldClose.
type Dispositions interface {
	Close(bead string, d Disposition, note string) error
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
// ruled, or a move since the writer read the bead. The next run tries again.
type HeldClose struct{ Why string }

func (e *HeldClose) Error() string { return e.Why }

// Landing is what the record's verbs act through. Dir is the store's .beads
// directory, where the record lock lives, and Refinery the assignee of a bead
// the refinery holds. Feedback loads the definition of feedback, once a run
// first needs it. Mark reads the city's mark, which a dismissal's message
// carries, from the writer that owns it. Runs pours a PR's review run, and
// Dispositions closes a bead whose PR a ruling retired. Audit is the rig's
// seed audit, nil for a rig whose repository carries none. Wait bounds how
// long a writer waits for the lock, and Yield is how long a run lets the lock
// stand free between two records, so a writer waiting for it takes it.
type Landing struct {
	Ledger       *ledger.Ledger
	Dir          string
	Refinery     string
	Hub          func(host string) Hub
	Feedback     func() (Feedback, error)
	Mark         func() (string, error)
	Checkout     Checkout
	Gates        Gates
	Runs         Runs
	Dispositions Dispositions
	Audit        Audit
	Now          func() time.Time
	Wait         time.Duration
	Yield        time.Duration
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
	record.Publish(publish, p, l.stamp())
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
	// ActChecked: the PR stands as the record says, and the run recorded the read.
	ActChecked = "checked"
	// ActRequested: the evaluator found the PR ready, and the run asked GitHub to
	// merge it, or to add it to its base's merge queue, at the head it judged.
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
	// ActRetry: the read could not decide, and the next run reads it again.
	ActRetry = "retry"
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
	// ActFailed: a write or a read failed in a way the next run may not clear.
	ActFailed = "failed"
)

// Options bound one run: the most records it reads, and the time after which it
// starts no other.
type Options struct {
	Count    int
	Deadline time.Time
}

// Reconcile is one run of the landing order. It lists the beads that carry the
// marker, and the beads on the record that carry a ruling's disposition, takes
// up to o.Count of them, the least recently checked first, and reads each under
// the record lock, from its read of the record to its last write of it, waiting
// while another writer holds the lock. A bead whose PR closed under a ruling's
// disposition goes to the disposition writer once the lock is released. A
// record that lands on the rig's default branch has the branch's seed audit
// checked once the lock is released, and its outcome says what the check found.
// It reports each record's outcome to report as it goes, and returns an error
// when the listing or a lock did not answer, or when a record's outcome failed.
func (l Landing) Reconcile(o Options, report func(RunOutcome)) error {
	ids, err := l.due(o.Count)
	if err != nil {
		return err
	}
	run := &run{Landing: l}
	failed := 0
	for i, id := range ids {
		if !o.Deadline.IsZero() && !time.Now().Before(o.Deadline) {
			report(RunOutcome{Bead: id, Action: ActSkipped,
				Detail: fmt.Sprintf("the run reached its deadline; %d records wait for the next run", len(ids)-i)})
			break
		}
		run.landed, run.disposal = nil, nil
		out, err := run.one(id)
		if err != nil {
			return fmt.Errorf("%s: %w", id, err)
		}
		if run.disposal != nil {
			out = run.dispose(*run.disposal, out)
		}
		if out.Action == ActFailed {
			failed++
		}
		if run.landed != nil {
			out.Detail += run.audit(*run.landed, o.Deadline)
		}
		report(out)
		if l.Yield > 0 && i < len(ids)-1 {
			time.Sleep(l.Yield)
		}
	}
	if failed > 0 {
		return fmt.Errorf("%d of the records read failed", failed)
	}
	return nil
}

// due lists the records a run reads: the beads carrying the marker set true,
// open, blocked or closed, and the beads a run reads for a ruling's disposition
// (disposing), marker or none, so a changed head the order settled is read
// again until its PR closes. The least recently checked come first, up to
// count.
func (l Landing) due(count int) ([]string, error) {
	rows, err := l.Ledger.Find(record.Marked())
	if err != nil {
		return nil, err
	}
	ruled, err := l.Ledger.Find(ledger.Carrying(dispositionKindKey))
	if err != nil {
		return nil, err
	}
	type due struct{ id, checked string }
	var all []due
	listed := map[string]bool{}
	for _, r := range rows {
		rec, err := record.Read(r)
		if err != nil || !rec.Marked {
			continue
		}
		switch r.Status() {
		case "open", "blocked", "closed":
			all = append(all, due{r.ID, rec.CheckedAt})
			listed[r.ID] = true
		}
	}
	for _, r := range ruled {
		rec, err := record.Read(r)
		if err != nil || listed[r.ID] || !l.disposing(r, rec) {
			continue
		}
		all = append(all, due{r.ID, rec.CheckedAt})
	}
	slices.SortStableFunc(all, func(a, b due) int {
		if c := strings.Compare(a.checked, b.checked); c != 0 {
			return c
		}
		return strings.Compare(a.id, b.id)
	})
	var ids []string
	for _, d := range all {
		if count > 0 && len(ids) == count {
			break
		}
		ids = append(ids, d.id)
	}
	return ids, nil
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
// and reads the city's mark once, when a record first needs each, and reads the
// login the city's account acts as once for each host. landed is the merge the
// record just read closed its bead on, for the seed audit's check once the lock
// is free, disposal the close the record just read owes the disposition writer
// once the lock is free, and audited names, for each tip of the default branch
// the run has checked, the bead whose landing checked it.
type run struct {
	Landing
	feedback Feedback
	mark     string
	logins   map[string]string
	landed   *landedMerge
	disposal *disposal
	audited  map[string]string
}

// landedMerge is a PR the run closed its bead on: the bead, the PR's number and
// the branch it merged into.
type landedMerge struct {
	bead, number, target string
}

// disposal is a bead whose PR closed under a ruling's disposition, which the
// run hands to the disposition writer: the bead, the disposition, and the note
// the close carries.
type disposal struct {
	bead, note string
	d          Disposition
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

// readHub is GitHub as the evaluator reads it on a run: the hub of the record's
// host, which answers the PR the run read just before it with that read and the
// login with the run's own, so the evaluator reads neither again. Its other
// reads go to GitHub.
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

// state is one record as a run read it under the lock: the bead's row and its
// record, the provenance instant the definition of feedback is applied from,
// the beads its blocks edges name, open and closed, the withdrawals filed on it
// and the review runs attached to it, live.
type state struct {
	id, status, assignee, branch string
	since                        string
	row                          *ledger.Record
	rec                          record.Record
	blockers                     []*ledger.Record
	withdrawals                  []withdrawal
	runs                         []string
	now                          string
}

// one reads one record under the lock and makes the writes it owes.
func (u *run) one(id string) (RunOutcome, error) {
	release, err := record.Lock(u.Dir, u.Wait)
	if err != nil {
		return RunOutcome{}, err
	}
	defer release()
	r, err := u.read(id)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the bead did not read: " + err.Error()}, nil
	}
	if r == nil {
		return RunOutcome{Bead: id, Action: ActSkipped, Detail: "the store no longer holds the bead"}, nil
	}
	rec, err := record.Read(r)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the record did not read: " + err.Error()}, nil
	}
	d, ruled, err := dispositionOf(r)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the disposition did not read: " + err.Error()}, nil
	}
	if !rec.Marked && !u.disposing(r, rec) {
		return RunOutcome{Bead: id, Action: ActSkipped, Detail: "the bead no longer carries the marker"}, nil
	}
	branch, _, err := record.Branch.Get(r)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the branch did not read: " + err.Error()}, nil
	}
	since, _, err := provenanceKey.Get(r)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the provenance instant did not read: " + err.Error()}, nil
	}
	s := state{id: id, status: r.Status(), assignee: r.Assignee(), branch: strings.TrimSpace(branch),
		since: strings.TrimSpace(since), row: r, rec: rec, now: u.stamp()}
	switch {
	case s.status == "closed":
		return u.closed(s), nil
	case s.assignee != u.Refinery:
		return u.released(s), nil
	case s.status != "open" && s.status != "blocked":
		return RunOutcome{Bead: id, Action: ActSkipped, Detail: "the bead's status " + s.status + " is none the record knows"}, nil
	}
	rows, err := u.blockers(r, true)
	if err == nil {
		s.blockers = rows
		s.withdrawals, err = withdrawalsIn(rows)
	}
	if err == nil {
		s.runs, err = runsIn(rows)
	}
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "what holds the bead did not read: " + err.Error()}, nil
	}
	switch {
	case ruled && record.OnRecord(rec.Result):
		return u.disposed(s, d), nil
	case s.status == "open":
		return u.open(s), nil
	}
	return u.blocked(s), nil
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

// closed handles a closed bead that still carries the marker. One closed on a
// verified merge owes nothing more, and its marker clears. Any other is a close
// that took no lock and reached the bead with no verified merge, which a run
// reopens as blocked, behind a gate.
func (u *run) closed(s state) RunOutcome {
	if s.rec.Result == record.Merged && mergeEvidence(s.rec) {
		w := u.Ledger.Write(s.id)
		record.Unmark(w, "")
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActSettled,
			Detail: "closed on a verified merge at " + s.rec.MergedSHA + ": the marker is cleared"})
	}
	pr := firstOf(s.rec.URL, s.rec.ExistingPR, "its pull request")
	return u.except(s, record.LegacyClosed, "legacy_closed_unverified",
		fmt.Sprintf("%s closed while it carried the pending record of %s, with no verified merge", s.id, pr),
		fmt.Sprintf("%s was closed while it still carried the pending record of %s, and no merge was verified, so "+
			"the landing order reopened it as blocked, and what waits on it stays held. Check whether the pull "+
			"request merged into its target. If it did, close %s again as landed. If it did not, decide whether "+
			"the work goes back to the refinery or stands down.", s.id, pr, s.id))
}

// open handles an open bead the refinery holds. A changed head already waits on
// the refinery, and its marker clears, unless a withdrawal is open on it, which
// holds it from the refinery until the run carries it out. A whole record whose
// second write landed moves to blocked and is read on. Anything else is a
// record a dead writer left half written, which goes back to the refinery for
// its full validation.
func (u *run) open(s state) RunOutcome {
	switch {
	case s.rec.Result == record.HeadChanged && withdrawing(s):
		return u.requeued(s)
	case s.rec.Result == record.HeadChanged:
		w := u.Ledger.Write(s.id)
		record.Settle(w)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActSettled,
			Detail: "its changed head already waits on the refinery's validation: the marker is cleared"})
	case s.rec.Result == record.Pending && len(recordGaps(s.rec, s.branch)) == 0:
		w := u.Ledger.Write(s.id)
		record.Block(w)
		done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActBlocked, Detail: "the whole record had landed on an open bead"})
		if done.Action != ActBlocked {
			return done
		}
		s.status = "blocked"
		return u.blocked(s)
	}
	w := u.Ledger.Write(s.id)
	record.Revalidate(w, "Interrupted PR handoff record is incomplete; full refinery validation is required", s.now)
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRevalidate,
		Detail: "the record was half written: the bead goes back to the refinery, and no merge is requested"})
}

// withdrawing reports whether a withdrawal is open on the record s read.
func withdrawing(s state) bool {
	return slices.ContainsFunc(s.withdrawals, func(w withdrawal) bool { return w.open })
}

// requeued handles a changed head the run sent back to the refinery while a
// withdrawal is open on it. It reads the PR by its number and carries the
// withdrawal out while the PR is open, keeping the marker until none is open,
// so the bead goes to the refinery once nothing the order owes holds it, and a
// check that keeps the marker saves GitHub's side as read after the carry. A PR
// that closed or merged meanwhile is the record's exception, as on a pending
// record.
func (u *run) requeued(s state) RunOutcome {
	r := s.rec
	retry := func(state, why string) RunOutcome {
		w := u.Ledger.Write(s.id)
		record.Retry(w, state, why, s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: why})
	}
	if missing := recordGaps(r, s.branch); len(missing) > 0 {
		return u.invalid(s, "the requeued record is incomplete: it lacks "+strings.Join(missing, ", "))
	}
	host, _, number, _ := record.ParseURL(r.URL)
	if why := u.originDiffers(host, r.Repo); why != "" {
		return retry("origin_mismatch", why+"; will retry")
	}
	hub := u.Hub(host)
	p, err := hub.PullRequest(r.Repo, number)
	if err != nil {
		return retry("lookup_failed", "GitHub PR lookup failed; will retry: "+err.Error())
	}
	if ids := identityGaps(p, r.URL, number, r.Repo, s.branch, r.Target); len(ids) > 0 {
		return u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
	}
	switch p.State {
	case "OPEN":
		note, held := u.carry(s, host, hub, p)
		if held {
			gr, out, ok := u.observeAlone(s, host, hub, p, retry)
			if !ok {
				out.Detail = withNote(out.Detail, note)
				return out
			}
			w := u.Ledger.Write(s.id)
			record.Checked(w, "open", s.now)
			githubReadKey.Set(w, gr)
			return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActChecked,
				Detail: "its changed head waits on the refinery, behind the withdrawal: " + note})
		}
		w := u.Ledger.Write(s.id)
		record.Settle(w)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActSettled,
			Detail: "its changed head waits on the refinery's validation, and the marker is cleared: " + note})
	case "CLOSED":
		return u.except(s, record.ClosedUnmerged, "closed_unmerged", "Pull request "+r.URL+" closed without merging.",
			fmt.Sprintf("Pull request %s closed without merging while a withdrawal of its approvals was open, so %s stays "+
				"blocked, and what waits on it stays held. Decide what becomes of the work: reopen the pull request and "+
				"send %s back to the refinery, or stand the work down.", r.URL, s.id, s.id))
	case "MERGED":
		return u.merged(s, p.HeadRefOid, p.MergeCommit, p.MergedAt, retry)
	}
	return retry("unknown", fmt.Sprintf("GitHub returned unknown PR state %q; will retry", p.State))
}

// blocked handles a blocked bead the refinery holds: the record must be whole
// and must read pending, or a verified merge whose close did not land. Its PR is
// read from GitHub by its number.
func (u *run) blocked(s state) RunOutcome {
	r := s.rec
	if record.Exception(r.Result) {
		// A run recorded the exception and stopped before its gate filed.
		message := fmt.Sprintf("%s %s stays blocked, and what waits on it stays held, until a person "+
			"decides what becomes of the work.", firstOf(r.BlockedReason, "The pending record met "+r.Result+"."), s.id)
		if r.Result == record.CloseRefused {
			message = refusedMessage(s.id, firstOf(r.BlockedReason, "A verified merge's close was refused"))
		}
		return u.gate(s, r.Result, message,
			RunOutcome{Bead: s.id, Action: ActExcepted, Detail: r.Result + ": the gate an earlier run did not file is filed"})
	}
	switch r.Result {
	case record.Pending:
		if missing := recordGaps(r, s.branch); len(missing) > 0 {
			return u.invalid(s, "the pending record is incomplete: it lacks "+strings.Join(missing, ", "))
		}
		if r.MergedSHA != "" || r.MergedAt != "" || r.State == "merged" {
			return u.invalid(s, "the pending record carries a merge's evidence")
		}
	case record.Merged:
		if !mergeEvidence(r) || len(recordGaps(r, s.branch)) > 0 {
			return u.invalid(s, "the record names a merge without its whole evidence")
		}
	default:
		return u.invalid(s, fmt.Sprintf("a blocked bead with a pending marker reads merge_result %q, not %s", r.Result, record.Pending))
	}
	// A retry of a recorded merge keeps the state it verified.
	retry := func(state, why string) RunOutcome {
		if r.Result == record.Merged {
			state = ""
		}
		w := u.Ledger.Write(s.id)
		record.Retry(w, state, why, s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: why})
	}
	host, _, number, _ := record.ParseURL(r.URL)
	if why := u.originDiffers(host, r.Repo); why != "" {
		return retry("origin_mismatch", why+"; will retry")
	}
	hub := u.Hub(host)
	p, err := hub.PullRequest(r.Repo, number)
	if err != nil {
		return retry("lookup_failed", "GitHub PR lookup failed; will retry: "+err.Error())
	}
	if ids := identityGaps(p, r.URL, number, r.Repo, s.branch, r.Target); len(ids) > 0 {
		return u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
	}
	if !record.IsObjectID(p.HeadRefOid) {
		return u.invalid(s, fmt.Sprintf("GitHub names the PR's head %q, which is no commit id", p.HeadRefOid))
	}
	switch p.State {
	case "OPEN":
		if r.Result == record.Merged {
			return u.contradiction(s, fmt.Sprintf("%s recorded a merge at %s, and GitHub reports the PR open", s.id, r.MergedSHA))
		}
		note, held := u.carry(s, host, hub, p)
		if p.HeadRefOid != r.Head {
			gr, out, ok := u.observeAlone(s, host, hub, p, retry)
			if !ok {
				out.Detail = withNote(out.Detail, note)
				return out
			}
			reason := fmt.Sprintf("PR head changed after refinery validation (%s -> %s); quality gates must run again", r.Head, p.HeadRefOid)
			w := u.Ledger.Write(s.id)
			record.Requeue(w, r.URL, p.HeadRefOid, reason, s.now, held)
			githubReadKey.Set(w, gr)
			return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRequeued, Detail: withNote(reason, note)})
		}
		return u.decide(s, host, hub, p, retry, note)
	case "CLOSED":
		return u.except(s, record.ClosedUnmerged, "closed_unmerged", "Pull request "+r.URL+" closed without merging.",
			fmt.Sprintf("Pull request %s closed without merging, so %s stays blocked, and what waits on it stays "+
				"held. Decide what becomes of the work: reopen the pull request and send %s back to the refinery, "+
				"or stand the work down.", r.URL, s.id, s.id))
	case "MERGED":
		return u.merged(s, p.HeadRefOid, p.MergeCommit, p.MergedAt, retry)
	}
	return retry("unknown", fmt.Sprintf("GitHub returned unknown PR state %q; will retry", p.State))
}

// disposed handles a bead on the record that carries the disposition a ruling
// recorded before it closed the PR (pr-dispose.sh). The PR will not land, so
// the run requests no merge, pours no review run and marks nothing ready,
// whatever GitHub says of it. It reads the PR by its number: one still open
// waits for its close, one that merged all the same lands as any merge does,
// and one that has closed is retired.
func (u *run) disposed(s state, d Disposition) RunOutcome {
	r := s.rec
	retry := func(state, why string) RunOutcome {
		w := u.Ledger.Write(s.id)
		record.Retry(w, state, why, s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: why})
	}
	if missing := recordGaps(r, s.branch); len(missing) > 0 {
		return u.invalid(s, "the record is incomplete: it lacks "+strings.Join(missing, ", "))
	}
	host, _, number, _ := record.ParseURL(r.URL)
	if why := u.originDiffers(host, r.Repo); why != "" {
		return retry("origin_mismatch", why+"; will retry")
	}
	p, err := u.Hub(host).PullRequest(r.Repo, number)
	if err != nil {
		return retry("lookup_failed", "GitHub PR lookup failed; will retry: "+err.Error())
	}
	if ids := identityGaps(p, r.URL, number, r.Repo, s.branch, r.Target); len(ids) > 0 {
		return u.invalid(s, "the PR on GitHub is not the one the record names: "+strings.Join(ids, ", "))
	}
	ruling := d.ruling()
	switch p.State {
	case "OPEN":
		w := u.Ledger.Write(s.id)
		record.Checked(w, "open", s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActChecked,
			Detail: ruling + ", so no merge is requested, and the PR's close finishes it"})
	case "CLOSED":
		return u.retire(s, d, p.Number, ruling, retry)
	case "MERGED":
		return u.merged(s, p.HeadRefOid, p.MergeCommit, p.MergedAt, retry)
	}
	return retry("unknown", fmt.Sprintf("GitHub returned unknown PR state %q; will retry", p.State))
}

// retire handles a PR a ruling retired once it has closed. While a review run
// is attached to the bead, the bead's close waits for the run to end. Otherwise
// the run closes the withdrawals and the asks still open on the bead, which
// nothing carries out or takes once the PR is closed, records the check, and
// owes the bead's own close to the disposition writer, which Reconcile hands it
// once the lock is free. A close of a withdrawal or an ask that does not land
// leaves the bead to the next run.
func (u *run) retire(s state, d Disposition, number int, ruling string, retry func(string, string) RunOutcome) RunOutcome {
	checked := func(detail string) RunOutcome {
		w := u.Ledger.Write(s.id)
		record.Checked(w, "closed", s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActChecked, Detail: detail})
	}
	closed := "the PR closed, and " + ruling
	if len(s.runs) > 0 {
		return checked(fmt.Sprintf("%s; the bead's close waits for the review run %s to end", closed, strings.Join(s.runs, ", ")))
	}
	asks, err := review.AsksIn(u.Ledger, s.row, s.blockers)
	if err != nil {
		return retry("closed", "the asks on the bead did not read; will retry: "+err.Error())
	}
	why := fmt.Sprintf("PR #%d closed under the disposition a ruling recorded on %s, %s onto %s", number, s.id, d.Kind, d.Successor)
	var moot []string
	for _, w := range s.withdrawals {
		if !w.open {
			continue
		}
		note := fmt.Sprintf("The landing order closed this withdrawal (%s): %s, so no approval it withdraws can merge it.", s.now, why)
		if err := u.moot(w.id, w.status, w.assignee, note); err != nil {
			return retry("closed", fmt.Sprintf("the withdrawal %s did not close; will retry: %v", w.id, err))
		}
		moot = append(moot, w.id)
	}
	for _, a := range asks {
		if !a.Open() {
			continue
		}
		note := fmt.Sprintf("The landing order closed this ask (%s): %s, so no review run takes it.", s.now, why)
		if err := u.moot(a.ID, a.Status, "", note); err != nil {
			return retry("closed", fmt.Sprintf("the ask %s did not close; will retry: %v", a.ID, err))
		}
		moot = append(moot, a.ID)
	}
	detail := closed
	if len(moot) > 0 {
		detail += fmt.Sprintf("; %s closed, which nothing takes now", strings.Join(moot, ", "))
	}
	out := checked(detail + "; the bead goes to the disposition writer")
	if out.Action == ActChecked {
		u.disposal = &disposal{bead: s.id, d: d,
			note: fmt.Sprintf("PR #%d closed under the disposition a ruling recorded before the close", number)}
	}
	return out
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
// what became of it: out, what the run recorded of the bead under the lock,
// with the writer's answer after it. A close the writer holds for now is the
// next run's to try again.
func (u *run) dispose(x disposal, out RunOutcome) RunOutcome {
	if u.Dispositions == nil {
		return RunOutcome{Bead: x.bead, Action: ActFailed, Detail: out.Detail + ", but no disposition writer is set"}
	}
	err := u.Dispositions.Close(x.bead, x.d, x.note)
	var held *HeldClose
	switch {
	case err == nil:
		return RunOutcome{Bead: x.bead, Action: ActDisposed, Detail: out.Detail + ", which closed it"}
	case errors.As(err, &held):
		return RunOutcome{Bead: x.bead, Action: ActRetry,
			Detail: out.Detail + ", which holds its close for now, and the next run tries again: " + held.Why}
	}
	return RunOutcome{Bead: x.bead, Action: ActFailed, Detail: out.Detail + ", which did not answer: " + err.Error()}
}

// observeAlone reads GitHub's side of the PR the run read a moment before, at
// the head it found, for a check the evaluator does not decide: a PR in its
// base's merge queue, one open at another head, or a draft the run marks ready.
// It reads through readHub, which answers the PR with that read and the login
// with the run's own. A read that does not answer, or a definition of feedback
// that does not load, writes the retry and leaves the GitHub read the bead
// holds, and ok is false.
func (u *run) observeAlone(s state, host string, hub Hub, p *gh.PullRequest, retry func(string, string) RunOutcome) (gr *GitHubRead, out RunOutcome, ok bool) {
	rule, err := u.rule()
	if err != nil {
		return nil, retry("lookup_failed", "the definition of feedback did not load; will retry: "+err.Error()), false
	}
	read := readHub{Hub: hub, pr: p, login: func() (string, error) { return u.login(host, hub) }}
	gr, err = observe(read, rule, s.rec.Repo, p.Number, s.since, u.stamp())
	if err != nil {
		return nil, retry("lookup_failed", fmt.Sprintf("GitHub's side of the PR at %s did not read; will retry: %v", p.HeadRefOid, err)), false
	}
	return gr, RunOutcome{}, true
}

// decide asks the evaluator whether a PR open at the validated head is ready,
// and asks GitHub to merge one that is, pinned to the head the answer judged,
// or to add it to its base's merge queue where the base requires one. A PR
// already in the queue has its merge requested, and is only observed. A draft
// the review loop has passed at its head, with no review run attached and no
// ask a run can take, is observed alone and marked ready first, so its saved
// read shows the draft until the next run reads it again (readyBar). A PR the
// evaluator finds not ready is owed a review run when it has no passed result
// at the head or an ask a run can take is open, which the run pours (admit).
// The evaluator reads the PR as blocked read it a moment before, and the run's
// login (readHub). Each write the check makes carries the GitHub read it made,
// after the request where it makes one. A read that does not answer leaves the
// read the bead holds, and so does a check that made none, because the
// evaluator's own pass of the store found the record lacking a part, which a
// writer that takes no lock can leave after the run's read. Whatever GitHub
// answers, the next run reads the PR again by its number. note is what the run
// did with the record's withdrawals, which each outcome carries.
func (u *run) decide(s state, host string, hub Hub, p *gh.PullRequest, retry func(string, string) RunOutcome, note string) RunOutcome {
	nodeID, inQueue, queue := p.ID, p.InMergeQueue, p.MergeQueueEnabled
	retried := func(state, why string) RunOutcome {
		o := retry(state, why)
		o.Detail = withNote(o.Detail, note)
		return o
	}
	checked := func(gr *GitHubRead, detail string) RunOutcome {
		w := u.Ledger.Write(s.id)
		record.Checked(w, "open", s.now)
		if gr != nil {
			githubReadKey.Set(w, gr)
		}
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActChecked, Detail: withNote(detail, note)})
	}
	if inQueue {
		gr, out, ok := u.observeAlone(s, host, hub, p, retried)
		if !ok {
			return out
		}
		return checked(gr, "the PR is in its base's merge queue, which holds its merge request")
	}
	asks, err := review.AsksIn(u.Ledger, s.row, s.blockers)
	if err != nil {
		return retried("lookup_failed", "the asks on the bead did not read; will retry: "+err.Error())
	}
	if p.IsDraft {
		results, _, err := review.Results.Get(s.row)
		if err != nil {
			return retried("lookup_failed", "the review results did not read; will retry: "+err.Error())
		}
		if readyBar(s, p, results, asks) == "" {
			gr, out, ok := u.observeAlone(s, host, hub, p, retried)
			if !ok {
				return out
			}
			if err := hub.MarkReady(nodeID); err != nil {
				w := u.Ledger.Write(s.id)
				why := fmt.Sprintf("the ready transition at %s was refused or not answered; the next run reads the draft flag again: %v", p.HeadRefOid, err)
				record.Retry(w, "open", why, s.now)
				githubReadKey.Set(w, gr)
				return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(why, note)})
			}
			w := u.Ledger.Write(s.id)
			record.Checked(w, "open", s.now)
			githubReadKey.Set(w, gr)
			return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActReadied, Detail: withNote(fmt.Sprintf(
				"marked ready at %s, without waiting for CI: a passed result names the head, and no review run is attached "+
					"and no ask a run can take is open; the next run reads the PR again", p.HeadRefOid), note)})
		}
	}
	rule, err := u.rule()
	if err != nil {
		return retried("lookup_failed", "the definition of feedback did not load; will retry: "+err.Error())
	}
	read := readHub{Hub: hub, pr: p, login: func() (string, error) { return u.login(host, hub) }}
	ans, gr, err := Ready(Sources{Ledger: u.Ledger, GitHub: func(h string) GitHub {
		if h == host {
			return read
		}
		return u.Hub(h)
	}, Feedback: rule, Now: u.Now}, s.id)
	if err != nil {
		return retried("lookup_failed", "the evaluator's read did not answer; will retry: "+err.Error())
	}
	if !ans.Ready {
		if out, owed := u.admit(s, p, ans, gr, asks, note); owed {
			return out
		}
		var not []string
		for _, c := range ans.Conditions {
			not = append(not, string(c.Kind))
		}
		return checked(gr, "not ready: "+strings.Join(slices.Compact(not), ", "))
	}
	// The merge request is the one act no guard can take back, so the bead is
	// read once more just before it: a close or a release that took no lock and
	// landed during the run's reads stops it here. One that lands after this
	// read is the residual the design names, a merge requested before the run
	// could read the release. A ruling's disposition takes the record lock, so
	// none lands while the run holds the record: one recorded before the run
	// read the bead took the run to disposed, and one that comes later waits
	// for the lock and lands after the request.
	now, err := u.read(s.id)
	if err != nil {
		return retried("lookup_failed", "the bead did not read again before the merge request; will retry: "+err.Error())
	}
	if now == nil || now.Status() != s.status || now.Assignee() != s.assignee {
		return RunOutcome{Bead: s.id, Action: ActMoved, Detail: withNote(
			"the bead moved during the run's reads, so no merge was requested; the next run reads it as it stands", note)}
	}
	method, ask := "merge", hub.MergePullRequest
	if queue {
		method, ask = "enqueue", hub.EnqueuePullRequest
	}
	if err := ask(nodeID, ans.Head); err != nil {
		w := u.Ledger.Write(s.id)
		why := fmt.Sprintf("the %s request at %s was refused or not answered; the next run reads the PR again: %v", method, ans.Head, err)
		record.Retry(w, "open", why, s.now)
		githubReadKey.Set(w, gr)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(why, note)})
	}
	w := u.Ledger.Write(s.id)
	record.Checked(w, "open", s.now)
	githubReadKey.Set(w, gr)
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRequested,
		Detail: withNote(fmt.Sprintf("ready: the %s is requested at %s into %s", method, ans.Head, ans.Target), note)})
}

// withNote is detail with the run's account of the record's withdrawals after
// it, when the run carried any out.
func withNote(detail, note string) string {
	if note == "" {
		return detail
	}
	return detail + "; " + note
}

// merged closes the bead once the PR merged the validated head and the merge
// commit is on a freshly fetched target, and keeps the merge it closed on for
// the seed audit's check. A merge of another head is an exception, and a merge
// whose commit the target does not reach yet is read again by the next run.
func (u *run) merged(s state, head, commit, at string, retry func(string, string) RunOutcome) RunOutcome {
	r := s.rec
	if head != r.Head {
		return u.except(s, record.MergedUnvalidatedHead, "merged_unvalidated_head",
			fmt.Sprintf("Pull request %s merged a different head than refinery validated (%s -> %s).", r.URL, r.Head, head),
			fmt.Sprintf("Pull request %s merged at %s, a head the refinery did not validate (it validated %s), so %s "+
				"stays blocked, and what waits on it stays held. Check what merged into %s, then close %s as landed "+
				"or send the work back.", r.URL, head, r.Head, s.id, r.Target, s.id))
	}
	if !record.IsObjectID(commit) || at == "" {
		return retry("merged_unverified", "GitHub reported MERGED without complete merge evidence; will retry.")
	}
	if r.Result == record.Merged && (commit != r.MergedSHA || at != r.MergedAt) {
		return u.contradiction(s, fmt.Sprintf("the recorded merge %s at %s is not GitHub's %s at %s", r.MergedSHA, r.MergedAt, commit, at))
	}
	if err := u.Checkout.FetchBranch(r.Target); err != nil {
		return retry("merged_unverified", fmt.Sprintf("Could not fetch origin/%s to verify the PR merge; will retry: %v", r.Target, err))
	}
	on, err := u.Checkout.Reaches(commit, r.Target)
	if err != nil || !on {
		if r.Result == record.Merged && err == nil {
			return u.contradiction(s, fmt.Sprintf("the recorded merge commit %s is no longer on origin/%s", commit, r.Target))
		}
		why := fmt.Sprintf("PR merge commit %s is not reachable from origin/%s; will retry.", commit, r.Target)
		if err != nil {
			why = fmt.Sprintf("Whether PR merge commit %s is on origin/%s did not read; will retry: %v", commit, r.Target, err)
		}
		return retry("merge_unreachable", why)
	}
	number := r.Number
	landing := record.Landing{MergedSHA: commit, Target: r.Target, MergedAt: at}
	w := u.Ledger.Write(s.id)
	record.Land(w, landing, s.now, fmt.Sprintf("PR #%s merged to %s at %s (%s).", number, r.Target, short(commit), r.URL))
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
	return retry("", "the merge is verified, but the close did not land; will retry: "+err.Error())
}

// audit checks the seed audit on the rig's default branch once a PR has landed
// on it, and hands the pages stale there to the writer of the branch's
// re-render. It reads the branch at its tip as the run fetched it to verify the
// merge, so the check judges every merge on the branch, this one and any after
// it, and a tip already checked in this run is not checked again. It runs with
// the record lock free and holds nothing, whatever it finds: the bead has
// closed, and a check that does not run is asked for again at a later landing.
// It returns the clause the landing's outcome carries, none for a landing on
// another branch or a rig whose repository carries no audit.
func (u *run) audit(m landedMerge, deadline time.Time) string {
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
	if !deadline.IsZero() && !time.Now().Before(deadline) {
		return fmt.Sprintf("; the run reached its deadline, so the seed audit on %s was not checked, and a later "+
			"landing checks it", def)
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
	record.Refuse(w, l, reason, s.now)
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
func (u *run) invalid(s state, why string) RunOutcome {
	return u.except(s, record.Invalid, "invalid", why,
		fmt.Sprintf("The pending record on %s no longer matches its pull request: %s. %s stays blocked, and what "+
			"waits on it stays held. Correct the record or the pull request, or stand the work down.", s.id, why, s.id))
}

// contradiction keeps a recorded merge GitHub's facts contradict blocked behind
// its gate.
func (u *run) contradiction(s state, why string) RunOutcome {
	return u.except(s, record.EvidenceContradiction, "merge_evidence_contradiction", why,
		fmt.Sprintf("GitHub's merge facts contradict the merge recorded on %s: %s. %s stays blocked, and what waits "+
			"on it stays held. Check what merged into %s before closing it.", s.id, why, s.id, firstOf(s.rec.Target, "the target")))
}

// except records the exception with the bead blocked, guarded on what the run
// read, then files the human gate keyed by it and clears the marker. A bead that
// moved since the read gets neither the record nor the gate.
func (u *run) except(s state, result, prState, reason, message string) RunOutcome {
	w := u.Ledger.Write(s.id)
	record.Except(w, result, prState, reason, s.now)
	done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActExcepted, Detail: result + ": " + reason})
	if done.Action != ActExcepted {
		return done
	}
	s.status = "blocked"
	return u.gate(s, result, message, done)
}

// gate files the exception's human gate on a bead the record already holds
// blocked, then clears the marker. A gate that does not file leaves the marker,
// so the next run files it.
func (u *run) gate(s state, result, message string, done RunOutcome) RunOutcome {
	if err := u.Gates.File(s.id, result, message); err != nil {
		w := u.Ledger.Write(s.id)
		why := fmt.Sprintf("%s: the human gate did not file; the next run files it: %v", result, err)
		record.Retry(w, "", why, s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: why})
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

// originDiffers says why a PR on host in repo is not in the repository the
// clone's origin names, or why the origin did not read, and is empty when the
// PR is in it.
func (l Landing) originDiffers(host, repo string) string {
	raw, err := l.Checkout.OriginURL()
	if err != nil {
		return "the rig's origin did not read: " + err.Error()
	}
	return outsideOrigin(raw, host, repo)
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

// mergeEvidence reports whether a recorded merge is whole: its commit, its
// state and its time.
func mergeEvidence(r record.Record) bool {
	return record.IsObjectID(r.MergedSHA) && r.State == "merged" && r.MergedAt != ""
}

// nobody names an assignee, "nobody" for none.
func nobody(a string) string {
	if a == "" {
		return "nobody"
	}
	return a
}
