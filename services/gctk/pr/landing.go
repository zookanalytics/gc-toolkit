package pr

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The landing order and the publication it reads (specs/tk-1tfzr71.66/design.md,
// sections 4 and 6). The refinery publishes a PR's pending record with Record,
// and the landing order's runs read each record with Reconcile: they request
// the merge of a PR the evaluator finds ready, close the bead once the merge
// commit is on the target, send a changed head back to the refinery, and keep
// the exceptions blocked behind a human gate. Both take the store's record
// lock, Record across both of its writes and a run for one record at a time,
// and every write they make carries bd's guards on the status and the assignee
// read under the lock, so neither writes over a bead that a close or a release
// reached first.

// Hub is GitHub as the landing order reaches it: the evaluator's reads, and a
// merge request or an enqueue pinned to the head it judged.
type Hub interface {
	GitHub
	MergePullRequest(id, head string) error
	EnqueuePullRequest(id, head string) error
}

// Checkout is the rig's clone, as the record reads it: its origin, the target
// it fetches, and whether a merge commit is on the target fetched.
type Checkout interface {
	OriginURL() (string, error)
	FetchBranch(branch string) error
	Reaches(commit, branch string) (bool, error)
}

// Gates files a human gate on a bead under a key, or finds the one open there.
type Gates interface {
	File(subject, key, message string) error
}

// Landing is what the record's verbs act through. Dir is the store's .beads
// directory, where the record lock lives, and Refinery the assignee of a bead
// the refinery holds. Feedback loads the definition of feedback, once a run
// first needs the evaluator. Wait bounds how long a writer waits for the lock,
// and Yield is how long a run lets the lock stand free between two records, so
// a writer waiting for it takes it.
type Landing struct {
	Ledger   *ledger.Ledger
	Dir      string
	Refinery string
	Hub      func(host string) Hub
	Feedback func() (Feedback, error)
	Checkout Checkout
	Gates    Gates
	Now      func() time.Time
	Wait     time.Duration
	Yield    time.Duration
}

// stamp is the time a write records, RFC 3339 UTC to the second, the form whose
// order is its text's order.
func (l Landing) stamp() string {
	now := time.Now
	if l.Now != nil {
		now = l.Now
	}
	return now().UTC().Format("2006-01-02T15:04:05Z")
}

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
	// ActLanded: the merge commit is on the target, and the bead closed.
	ActLanded = "landed"
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
// marker, takes up to o.Count of them, the least recently checked first, and
// reads each under the record lock, from its read of the record to its last
// write of it, waiting while another writer holds the lock. It reports each
// record's outcome to report as it goes, and returns an error when the listing
// or a lock did not answer, or when a record's outcome failed.
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
		out, err := run.one(id)
		if err != nil {
			return fmt.Errorf("%s: %w", id, err)
		}
		if out.Action == ActFailed {
			failed++
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
// open, blocked or closed, the least recently checked first, up to count.
func (l Landing) due(count int) ([]string, error) {
	rows, err := l.Ledger.Find(record.Marked())
	if err != nil {
		return nil, err
	}
	type due struct{ id, checked string }
	var all []due
	for _, r := range rows {
		rec, err := record.Read(r)
		if err != nil || !rec.Marked {
			continue
		}
		switch r.Status() {
		case "open", "blocked", "closed":
			all = append(all, due{r.ID, rec.CheckedAt})
		}
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
// once, when a record first needs the evaluator.
type run struct {
	Landing
	feedback Feedback
}

// state is one record as a run read it under the lock.
type state struct {
	id, status, assignee, branch string
	rec                          record.Record
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
	if !rec.Marked {
		return RunOutcome{Bead: id, Action: ActSkipped, Detail: "the bead no longer carries the marker"}, nil
	}
	branch, _, err := branchKey.Get(r)
	if err != nil {
		return RunOutcome{Bead: id, Action: ActFailed, Detail: "the branch did not read: " + err.Error()}, nil
	}
	s := state{id: id, status: r.Status(), assignee: r.Assignee(), branch: strings.TrimSpace(branch), rec: rec,
		now: u.stamp()}
	switch {
	case s.status == "closed":
		return u.closed(s), nil
	case s.assignee != u.Refinery:
		return u.released(s), nil
	case s.status == "open":
		return u.open(s), nil
	case s.status == "blocked":
		return u.blocked(s), nil
	}
	return RunOutcome{Bead: id, Action: ActSkipped, Detail: "the bead's status " + s.status + " is none the record knows"}, nil
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
// the refinery, and its marker clears. A whole record whose second write landed
// moves to blocked and is read on. Anything else is a record a dead writer left
// half written, which goes back to the refinery for its full validation.
func (u *run) open(s state) RunOutcome {
	switch {
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

// blocked handles a blocked bead the refinery holds: the record must be whole
// and must read pending, or a verified merge whose close did not land. Its PR is
// read from GitHub by its number.
func (u *run) blocked(s state) RunOutcome {
	r := s.rec
	if record.Exception(r.Result) {
		// A run recorded the exception and stopped before its gate filed.
		return u.gate(s, r.Result, fmt.Sprintf("%s %s stays blocked, and what waits on it stays held, until a person "+
			"decides what becomes of the work.", firstOf(r.BlockedReason, "The pending record met "+r.Result+"."), s.id),
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
		if p.HeadRefOid != r.Head {
			reason := fmt.Sprintf("PR head changed after refinery validation (%s -> %s); quality gates must run again", r.Head, p.HeadRefOid)
			w := u.Ledger.Write(s.id)
			record.Requeue(w, r.URL, p.HeadRefOid, reason, s.now)
			return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRequeued, Detail: reason})
		}
		return u.decide(s, hub, p.ID, p.InMergeQueue, p.MergeQueueEnabled, retry)
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

// decide asks the evaluator whether a PR open at the validated head is ready,
// and asks GitHub to merge one that is, pinned to the head the answer judged,
// or to add it to its base's merge queue where the base requires one. A PR
// already in the queue has its merge requested. Whatever GitHub answers, the
// next run reads the PR again by its number.
func (u *run) decide(s state, hub Hub, nodeID string, inQueue, queue bool, retry func(string, string) RunOutcome) RunOutcome {
	checked := func(detail string) RunOutcome {
		w := u.Ledger.Write(s.id)
		record.Checked(w, "open", s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActChecked, Detail: detail})
	}
	if inQueue {
		return checked("the PR is in its base's merge queue, which holds its merge request")
	}
	if u.feedback == nil {
		rule, err := u.Feedback()
		if err != nil {
			return retry("lookup_failed", "the definition of feedback did not load; will retry: "+err.Error())
		}
		u.feedback = rule
	}
	ans, err := Ready(Sources{Ledger: u.Ledger, GitHub: func(host string) GitHub { return u.Hub(host) }, Feedback: u.feedback}, s.id)
	if err != nil {
		return retry("lookup_failed", "the evaluator's read did not answer; will retry: "+err.Error())
	}
	if !ans.Ready {
		var not []string
		for _, c := range ans.Conditions {
			not = append(not, string(c.Kind))
		}
		return checked("not ready: " + strings.Join(slices.Compact(not), ", "))
	}
	// The merge request is the one act no guard can take back, so the bead is
	// read once more just before it: a close or a release that took no lock and
	// landed during the run's reads stops it here. One that lands after this
	// read is the residual the design names, a merge requested before the run
	// could read the release.
	now, err := u.read(s.id)
	if err != nil {
		return retry("lookup_failed", "the bead did not read again before the merge request; will retry: "+err.Error())
	}
	if now == nil || now.Status() != s.status || now.Assignee() != s.assignee {
		return RunOutcome{Bead: s.id, Action: ActMoved,
			Detail: "the bead moved during the run's reads, so no merge was requested; the next run reads it as it stands"}
	}
	method, ask := "merge", hub.MergePullRequest
	if queue {
		method, ask = "enqueue", hub.EnqueuePullRequest
	}
	if err := ask(nodeID, ans.Head); err != nil {
		w := u.Ledger.Write(s.id)
		why := fmt.Sprintf("the %s request at %s was refused or not answered; the next run reads the PR again: %v", method, ans.Head, err)
		record.Retry(w, "open", why, s.now)
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: why})
	}
	w := u.Ledger.Write(s.id)
	record.Checked(w, "open", s.now)
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRequested,
		Detail: fmt.Sprintf("ready: the %s is requested at %s into %s", method, ans.Head, ans.Target)})
}

// merged closes the bead once the PR merged the validated head and the merge
// commit is on a freshly fetched target. A merge of another head is an
// exception, and a merge whose commit the target does not reach yet is read
// again by the next run.
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
	w := u.Ledger.Write(s.id)
	record.Land(w, record.Landing{MergedSHA: commit, Target: r.Target, MergedAt: at}, s.now,
		fmt.Sprintf("PR #%s merged to %s at %s (%s).", number, r.Target, short(commit), r.URL))
	done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActLanded,
		Detail: fmt.Sprintf("PR #%s merged to %s at %s: the bead is closed", number, r.Target, short(commit))})
	if done.Action == ActFailed {
		// bd refused the close, such as for a live blocker or an open child, and
		// wrote nothing, so the record stands and the next run tries again.
		retryOut := retry("", "the merge is verified, but the close did not land; will retry: "+done.Detail)
		if retryOut.Action == ActRetry {
			return retryOut
		}
	}
	return done
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
