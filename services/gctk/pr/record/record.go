// Package record is Gas Town's pending-through-merge record on the bead that
// owns a pull request (gastown/commands/pr-merge-reconcile/run.sh in
// gascity-packs at 7f86098c04ea), in the pr domain: the record's keys, the
// values its merge_result takes, the writes that set them, and the store's
// record lock that every writer of the record takes. The pr domain's verbs
// decide which write a bead gets. This package says what each write sets, so
// the record's keys are declared and spelled here alone.
//
// Other domains read the record through Read, or through the reading faces of
// the keys whose value is their whole question (Result, PRURL, PRNumber,
// Rejection, Target) and the selection OnTarget, and write none of it.
package record

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The values merge_result takes on the record, with Gas Town's meanings
// (specs/tk-1tfzr71.66/design.md, section 6).
const (
	// Pending: the PR is open at the head the refinery validated, and the bead
	// waits on its merge, blocked and assigned to the refinery.
	Pending = "pull_request_pending"
	// HeadChanged: the PR is open at a head the refinery has not validated. The
	// bead is open and assigned to the refinery, which validates the new head.
	HeadChanged = "pull_request_head_changed"
	// Merged: the PR merged the validated head, and the merge commit is on the
	// target. The bead is closed.
	Merged = "mr_merged"
	// Incomplete: a writer that died between the publication's two writes left
	// the record half written, so the bead goes back to the refinery to be
	// validated again.
	Incomplete = "pull_request_record_incomplete"
	// Invalid: the PR's URL, number, branch or base no longer match the record,
	// or the record cannot be read as one.
	Invalid = "pull_request_reconcile_invalid"
	// ClosedUnmerged: the PR closed without merging.
	ClosedUnmerged = "pull_request_closed_unmerged"
	// MergedUnvalidatedHead: the PR merged a head the refinery did not validate.
	MergedUnvalidatedHead = "pull_request_merged_unvalidated_head"
	// EvidenceContradiction: GitHub's merge facts contradict a recorded merge.
	EvidenceContradiction = "pull_request_merge_evidence_contradiction"
	// LegacyClosed: a closed bead that still carries the marker and records no
	// verified merge, such as one a close that took no lock reached between
	// the publication's two writes.
	LegacyClosed = "pull_request_legacy_closed_unverified"
)

// OnRecord reports whether a bead whose merge_result is v owns a PR open on the
// record, at the head the refinery validated or at one it has not.
func OnRecord(v string) bool { return v == Pending || v == HeadChanged }

// Exception reports whether v is one of the record's exceptions, each of which
// keeps the bead blocked behind a human gate keyed by v.
func Exception(v string) bool {
	switch v {
	case Invalid, ClosedUnmerged, MergedUnvalidatedHead, EvidenceContradiction, LegacyClosed:
		return true
	}
	return false
}

// Record is the record a bead carries, each value as it is stored, "" where the
// bead carries none. Marked is whether it carries pr_reconcile_pending=true,
// the marker that a reconciliation is still owed.
type Record struct {
	Result                   string
	URL, Number, Repo        string
	Head, Observed           string
	State, CheckedAt         string
	Target                   string
	MergedSHA, MergedAt      string
	ExistingPR               string
	BlockedReason, Rejection string
	Error                    string
	Marked                   bool
}

// Read reads the record r carries. A value that does not decode is an error.
func Read(r *ledger.Record) (Record, error) {
	var err error
	get := func(k ledger.Key[string]) string {
		v, _, e := k.Get(r)
		if e != nil && err == nil {
			err = e
		}
		return strings.TrimSpace(v)
	}
	rec := Record{
		Result: get(mergeResultKey), URL: get(prURLKey), Number: get(prNumberKey), Repo: get(prRepoKey),
		Head: get(prHeadKey), Observed: get(observedHeadKey), State: get(prStateKey), CheckedAt: get(checkedAtKey),
		Target: get(mergedTargetKey), MergedSHA: get(mergedSHAKey), MergedAt: get(mergedAtKey),
		ExistingPR: get(existingPRKey), BlockedReason: get(blockedReasonKey), Rejection: get(rejectionReasonKey),
		Error: get(reconcileErrorKey), Marked: get(pendingKey) == "true",
	}
	return rec, err
}

// Marked selects the beads that carry the marker, closed ones among them,
// whatever value it holds: a reader keeps the ones whose record reads Marked.
func Marked() ledger.Selection { return ledger.Carrying(pendingKey).WithClosed() }

// The writes. Each sets what one act of the record sets, and the verb that
// makes it adds the guard on what it read.

// Arm is the first of a publication's two writes, made while the bead is still
// open: the marker, and the PR the refinery may reuse, so a writer that dies
// before the second write leaves an open bead that names its PR, never a
// blocked bead with half a record.
func Arm(w *ledger.Write, prURL string) {
	pendingKey.Set(w, "true")
	existingPRKey.Set(w, prURL)
}

// Publication is the PR a publication records: its URL, number and repository,
// the head the refinery validated, and the branch it is to merge into.
type Publication struct {
	URL, Repo, Head, Target string
	Number                  int
}

// Publish is the publication's second write, the whole record in one write: the
// bead blocked, merge_result pending, the PR's identity, the validated head and
// the target, with the marker set again in case a recovery cleared it between
// the two writes, and the evidence of an earlier round cleared.
func Publish(w *ledger.Write, p Publication, now string) {
	w.Status("blocked")
	pendingKey.Set(w, "true")
	mergeResultKey.Set(w, Pending)
	prURLKey.Set(w, p.URL)
	prNumberKey.Set(w, strconv.Itoa(p.Number))
	prHeadKey.Set(w, p.Head)
	prRepoKey.Set(w, p.Repo)
	prStateKey.Set(w, "open")
	checkedAtKey.Set(w, now)
	mergedTargetKey.Set(w, p.Target)
	blockedReasonKey.Set(w, "Awaiting verified merge of "+p.URL)
	for _, k := range []ledger.Key[string]{rejectionReasonKey, reconcileErrorKey, mergedSHAKey, mergedAtKey,
		existingPRKey, observedHeadKey} {
		k.Clear(w)
	}
}

// Block finishes a publication whose second write landed and whose bead is
// still open: the bead moves to blocked.
func Block(w *ledger.Write) { w.Status("blocked") }

// Checked records a read of the PR that leaves the record standing: the PR's
// state and when it was read, with any earlier error cleared.
func Checked(w *ledger.Write, state, now string) {
	prStateKey.Set(w, state)
	checkedAtKey.Set(w, now)
	reconcileErrorKey.Clear(w)
}

// Retry records a read that could not decide, which the next run reads again:
// when it was read and why it could not decide, and, unless state is empty, the
// PR's state as the read left it.
func Retry(w *ledger.Write, state, reason, now string) {
	if state != "" {
		prStateKey.Set(w, state)
	}
	checkedAtKey.Set(w, now)
	reconcileErrorKey.Set(w, reason)
}

// Requeue sends a PR open at a head the refinery has not validated back to the
// refinery: the bead open, merge_result head changed, the head found, and why,
// keeping the validated head. The marker goes, because the refinery's next
// publication arms it again.
func Requeue(w *ledger.Write, prURL, observed, reason, now string) {
	w.Status("open")
	mergeResultKey.Set(w, HeadChanged)
	existingPRKey.Set(w, prURL)
	observedHeadKey.Set(w, observed)
	prStateKey.Set(w, "open")
	checkedAtKey.Set(w, now)
	rejectionReasonKey.Set(w, reason)
	for _, k := range []ledger.Key[string]{blockedReasonKey, reconcileErrorKey, pendingKey} {
		k.Clear(w)
	}
}

// Settle clears the marker of an open bead whose changed head already waits on
// the refinery's validation, as Gas Town's recovery of an interrupted requeue
// does.
func Settle(w *ledger.Write) {
	for _, k := range []ledger.Key[string]{pendingKey, blockedReasonKey, reconcileErrorKey} {
		k.Clear(w)
	}
}

// Revalidate sends a half-written record back to the refinery for its full
// validation: merge_result incomplete, why, and the partial evidence and the
// marker cleared, keeping the PR the refinery may reuse so it opens no second
// one.
func Revalidate(w *ledger.Write, reason, now string) {
	w.Status("open")
	mergeResultKey.Set(w, Incomplete)
	prStateKey.Set(w, "revalidation_required")
	checkedAtKey.Set(w, now)
	rejectionReasonKey.Set(w, reason)
	for _, k := range []ledger.Key[string]{prURLKey, prNumberKey, prHeadKey, prRepoKey, mergedSHAKey,
		mergedTargetKey, mergedAtKey, observedHeadKey, blockedReasonKey, reconcileErrorKey, pendingKey} {
		k.Clear(w)
	}
}

// Except records one of the exceptions: the bead blocked, merge_result the
// exception, the PR's state and why. The marker stays until the verb has filed
// the human gate keyed by the exception and cleared it (Unmark), so a run that
// stops between the two leaves the gate for the next run to file.
func Except(w *ledger.Write, result, state, reason, now string) {
	w.Status("blocked")
	mergeResultKey.Set(w, result)
	prStateKey.Set(w, state)
	checkedAtKey.Set(w, now)
	blockedReasonKey.Set(w, reason)
}

// Landing is a merge the landing order verified: the merge commit, the target
// it was found on, and when GitHub says the PR merged.
type Landing struct {
	MergedSHA, Target, MergedAt string
}

// Land records the verified merge and closes the bead in one write, the marker
// cleared as the close lands, since the pack runs no artifact cleanup after the
// close. note rides the close as its reason, which bd's update does not set.
func Land(w *ledger.Write, l Landing, now, note string) {
	w.Status("closed")
	mergeResultKey.Set(w, Merged)
	mergedSHAKey.Set(w, l.MergedSHA)
	mergedTargetKey.Set(w, l.Target)
	prStateKey.Set(w, "merged")
	mergedAtKey.Set(w, l.MergedAt)
	checkedAtKey.Set(w, now)
	for _, k := range []ledger.Key[string]{rejectionReasonKey, reconcileErrorKey, blockedReasonKey, pendingKey} {
		k.Clear(w)
	}
	w.Note(note)
}

// Unmark clears the marker and nothing else, on a bead whose record needs no
// further run: one a release took from the refinery, which keeps its state, and
// one closed on a verified merge. note, when given, names the PR on the bead.
func Unmark(w *ledger.Write, note string) {
	pendingKey.Clear(w)
	if note != "" {
		w.Note(note)
	}
}

// Valid reports whether p names a PR the record can hold: a URL on a host,
// whose repository and number it names, a head that is a full object name, and
// a target.
func (p Publication) Valid() error {
	host, repo, number, ok := ParseURL(p.URL)
	switch {
	case !ok:
		return fmt.Errorf("%q is not a pull request's URL (https://<host>/<owner>/<repo>/pull/<number>)", p.URL)
	case host == "" || !strings.EqualFold(repo, p.Repo) || number != p.Number:
		return fmt.Errorf("the URL %s does not name %s#%d", p.URL, p.Repo, p.Number)
	case !IsObjectID(p.Head):
		return fmt.Errorf("%q is not a full commit id", p.Head)
	case p.Target == "":
		return fmt.Errorf("the publication names no target")
	}
	return nil
}
