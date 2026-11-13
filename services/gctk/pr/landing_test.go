package pr_test

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The landing order's cases follow Gas Town's pr-merge-reconcile tests at
// gascity-packs 7f86098c04ea (gastown/tests/test_pr_merge_reconcile.sh), each
// named for the case it ports, and add the pack's: the merge request, the merge
// queue, and the order of the record's writers under the store's record lock.
// Gas Town's cases about its artifact cleanup after the close, its REST lookup
// without gh, its witness's wake of the refinery and its formula's wiring have
// no counterpart: the pack runs no artifact cleanup, reads GitHub through gh,
// runs the order with no agent, and the refinery's formula is unit 4's.

const (
	refinery = "rig/refinery"
	merged   = "e111111111111111111111111111111111111111"
	origin   = "git@github.com:acme/widgets.git"
)

// checkout is the rig's clone as a test sets it: its origin, a fetch that fails
// when fetchErr is set, and the commits on the target once a fetch has run.
type checkout struct {
	mu        sync.Mutex
	origin    string
	fetchErr  error
	fetched   bool
	reachable map[string]bool
}

func (c *checkout) OriginURL() (string, error) { return c.origin, nil }

func (c *checkout) FetchBranch(string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.fetchErr != nil {
		return c.fetchErr
	}
	c.fetched = true
	return nil
}

func (c *checkout) Reaches(commit, _ string) (bool, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.fetched && c.reachable[commit], nil
}

// gates records each gate filed, and fails a filing when err is set.
type gates struct {
	mu    sync.Mutex
	filed []string
	err   error
}

func (g *gates) File(subject, key, _ string) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.err != nil {
		return g.err
	}
	g.filed = append(g.filed, subject+" "+key)
	return nil
}

func (g *gates) list() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.filed)
}

// land is one bead on the pending record, blocked and assigned to the refinery,
// whose PR the evaluator reads ready, with the landing order's sources.
type land struct {
	*world
	co    *checkout
	gates *gates
	l     pr.Landing
}

func newLand(t *testing.T) *land {
	t.Helper()
	w := ready()
	w.pr.Facts.ID = "PR_7"
	for k, v := range map[string]string{
		"pr_reconcile_pending": "true", "pr_state": "open", "pr_last_checked_at": "2026-11-12T01:00:00Z",
		"blocked_reason": "Awaiting verified merge of " + prURL,
	} {
		w.md[k] = v
	}
	co := &checkout{origin: origin, reachable: map[string]bool{merged: true}}
	g := &gates{}
	d := &land{world: w, co: co, gates: g}
	d.l = pr.Landing{
		Ledger:   ledger.New(w.store),
		Dir:      t.TempDir(),
		Refinery: refinery,
		Hub:      func(string) pr.Hub { return w.github },
		Feedback: func() (pr.Feedback, error) { return w.rule, nil },
		Checkout: co,
		Gates:    g,
		Now:      func() time.Time { return time.Date(2026, 11, 12, 9, 0, 0, 0, time.UTC) },
		Wait:     5 * time.Second,
	}
	d.put("blocked", refinery)
	return d
}

// put writes the bead's row with its record as the world holds it.
func (d *land) put(status, assignee string) {
	d.store.Put(fake.Bead{ID: bead, Title: "the work", Status: status, Assignee: assignee, Metadata: d.md, Edges: d.edges})
}

// row is the bead's row as the store holds it.
func (d *land) row(t *testing.T) fake.Bead {
	t.Helper()
	r, ok := d.store.Row(bead)
	if !ok {
		t.Fatal("the store lost the bead")
	}
	return r
}

// reconcile runs the landing order once and returns each outcome.
func (d *land) reconcile(t *testing.T, o pr.Options) []pr.RunOutcome {
	t.Helper()
	var out []pr.RunOutcome
	var mu sync.Mutex
	if err := d.l.Reconcile(o, func(x pr.RunOutcome) { mu.Lock(); out = append(out, x); mu.Unlock() }); err != nil {
		t.Fatalf("Reconcile: %v (outcomes %+v)", err, out)
	}
	return out
}

// once runs the landing order and returns the bead's one outcome.
func (d *land) once(t *testing.T) pr.RunOutcome {
	t.Helper()
	out := d.reconcile(t, pr.Options{Count: 10})
	if len(out) != 1 {
		t.Fatalf("one record, %d outcomes: %+v", len(out), out)
	}
	return out[0]
}

func is(t *testing.T, o pr.RunOutcome, action string) {
	t.Helper()
	if o.Action != action {
		t.Fatalf("outcome %s (%s), want %s", o.Action, o.Detail, action)
	}
}

func meta(t *testing.T, b fake.Bead, want map[string]string) {
	t.Helper()
	for k, v := range want {
		got, held := b.Metadata[k]
		switch {
		case v == "<absent>" && held:
			t.Errorf("%s = %q, want it absent", k, got)
		case v != "<absent>" && got != v:
			t.Errorf("%s = %q, want %q", k, got, v)
		}
	}
}

func asks(g *ghfake.GitHub) []string {
	var out []string
	for _, a := range g.Asks() {
		out = append(out, a.Method+" "+a.ID+" "+a.Head)
	}
	return out
}

func readsPR(g *ghfake.GitHub) bool { return slices.Contains(g.Reads(), "PullRequest") }

// publication is the PR the refinery publishes for the bead at h.
func publication(h string) record.Publication {
	return record.Publication{URL: prURL, Repo: repo, Number: 7, Head: h, Target: "main"}
}

// --- Gas Town's cases -------------------------------------------------------

func TestRecordBlocksWithoutClosing(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch, "merged_sha": "old", "pr_merged_at": "old", "observed_pr_head_sha": other,
		"rejection_reason": "an earlier round"}
	d.put("open", refinery)
	if err := d.l.Record(bead, publication(head)); err != nil {
		t.Fatal(err)
	}
	ws := d.store.Writes()
	if len(ws) != 2 {
		t.Fatalf("a publication is two writes, got %d: %+v", len(ws), ws)
	}
	arm, whole := strings.Join(ws[0].Args, " "), strings.Join(ws[1].Args, " ")
	for _, want := range []string{"--if-status=open", "--if-assignee=" + refinery, "pr_reconcile_pending=true", "existing_pr=" + prURL} {
		if !strings.Contains(arm, want) {
			t.Errorf("the first write %q lacks %q", arm, want)
		}
	}
	if strings.Contains(arm, "--status=") {
		t.Errorf("the first write moves the bead: %q", arm)
	}
	for _, want := range []string{"--if-status=open", "--status=blocked", "pr_reconcile_pending=true",
		"merge_result=pull_request_pending", "pr_head_sha=" + head} {
		if !strings.Contains(whole, want) {
			t.Errorf("the record's write %q lacks %q", whole, want)
		}
	}
	b := d.row(t)
	if b.Status != "blocked" || b.Assignee != refinery {
		t.Fatalf("recorded bead is %s under %s, want blocked under the refinery", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"merge_result": record.Pending, "pr_url": prURL, "pr_number": "7", "pr_repo": repo,
		"pr_head_sha": head, "pr_state": "open", "merged_target": "main", "pr_last_checked_at": "2026-11-12T09:00:00Z",
		"blocked_reason": "Awaiting verified merge of " + prURL, "pr_reconcile_pending": "true",
		"merged_sha": "<absent>", "pr_merged_at": "<absent>", "observed_pr_head_sha": "<absent>",
		"existing_pr": "<absent>", "rejection_reason": "<absent>"})
}

func TestRecordRefusesAPROutsideTheRigsOriginBeforeAnyWrite(t *testing.T) {
	d := newLand(t)
	d.co.origin = "https://github.com/example/other.git"
	err := d.l.Record(bead, publication(head))
	var origin *pr.OriginError
	if !errors.As(err, &origin) {
		t.Fatalf("a PR outside the rig's origin read as %v", err)
	}
	if len(d.store.Writes()) != 0 {
		t.Fatalf("the refusal wrote %+v", d.store.Writes())
	}
}

func TestAPartialRecordNeverBlocksWithoutTheWholeRecord(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch}
	d.put("open", refinery)
	n := 0
	d.store.BeforeUpdate = func(string, []string) error {
		if n++; n == 2 {
			return errors.New("the store did not answer")
		}
		return nil
	}
	err := d.l.Record(bead, publication(head))
	if err == nil || !strings.Contains(err.Error(), "the marker landed and the record did not") {
		t.Fatalf("a failed second write read as %v", err)
	}
	b := d.row(t)
	if b.Status != "open" {
		t.Fatalf("a failed record left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"pr_reconcile_pending": "true", "existing_pr": prURL, "merge_result": "<absent>"})
}

func TestOpenUnchangedPRStaysBlocked(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	is(t, d.once(t), pr.ActChecked)
	b := d.row(t)
	if b.Status != "blocked" || b.Assignee != refinery {
		t.Fatalf("an unchanged open PR left the bead %s under %s", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"pr_state": "open", "pr_last_checked_at": "2026-11-12T09:00:00Z", "pr_reconcile_pending": "true"})
	if len(d.github.Asks()) != 0 {
		t.Fatalf("a PR the evaluator holds was asked to merge: %v", asks(d.github))
	}
}

func TestReconcileOriginMismatchRetriesWithoutGitHubOrClose(t *testing.T) {
	d := newLand(t)
	d.co.origin = "git@github.com:example/other.git"
	o := d.once(t)
	is(t, o, pr.ActRetry)
	if readsPR(d.github) {
		t.Fatal("an origin mismatch read GitHub")
	}
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("an origin mismatch left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"pr_state": "origin_mismatch", "pr_reconcile_pending": "true"})
	if b.Metadata["pr_reconcile_error"] == "" {
		t.Fatal("the retry recorded no error")
	}
}

// A writer that died between the publication's two writes left an open bead
// with only the marker and the PR to reuse. The run sends it back to the
// refinery as half written and requests no merge.
func TestAMarkerOnlyOpenRecordGoesBackForRevalidation(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch, "pr_reconcile_pending": "true", "existing_pr": prURL,
		"pr_url": prURL, "pr_head_sha": head}
	d.put("open", refinery)
	is(t, d.once(t), pr.ActRevalidate)
	b := d.row(t)
	if b.Status != "open" || b.Assignee != refinery {
		t.Fatalf("a half-written record left the bead %s under %s", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"merge_result": record.Incomplete, "existing_pr": prURL, "pr_url": "<absent>",
		"pr_head_sha": "<absent>", "pr_reconcile_pending": "<absent>", "pr_state": "revalidation_required"})
	if b.Metadata["rejection_reason"] == "" {
		t.Fatal("the bead goes back with no reason")
	}
	if readsPR(d.github) || len(d.github.Asks()) != 0 {
		t.Fatalf("a half-written record read GitHub %v or asked %v", d.github.Reads(), asks(d.github))
	}
}

func TestACompleteOpenPendingRecordFinishesItsBlockFirst(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	d.put("open", refinery)
	is(t, d.once(t), pr.ActChecked)
	ws := d.store.Writes()
	if len(ws) < 1 || !slices.Contains(ws[0].Args, "--status=blocked") {
		t.Fatalf("the first write did not finish the block: %+v", ws)
	}
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
	if d.row(t).Status != "blocked" {
		t.Fatal("the bead is not blocked")
	}
}

func TestAChangedHeadOpenMarkerIsSettled(t *testing.T) {
	d := newLand(t)
	d.md["merge_result"] = record.HeadChanged
	d.md["observed_pr_head_sha"] = other
	d.put("open", refinery)
	is(t, d.once(t), pr.ActSettled)
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
	if d.row(t).Status != "open" || readsPR(d.github) {
		t.Fatalf("the settle moved the bead or read GitHub: %s, %v", d.row(t).Status, d.github.Reads())
	}
}

func TestAnInvalidBlockedRecordIsAnExceptionBeforeLookup(t *testing.T) {
	for _, result := range []string{"", "pull_request", "merged", record.Invalid, record.Merged} {
		t.Run(result, func(t *testing.T) {
			d := newLand(t)
			if result == "" {
				delete(d.md, "merge_result")
			} else {
				d.md["merge_result"] = result
			}
			d.put("blocked", refinery)
			is(t, d.once(t), pr.ActExcepted)
			b := d.row(t)
			want := map[string]string{"merge_result": record.Invalid, "pr_state": "invalid", "pr_reconcile_pending": "<absent>"}
			if result == record.Invalid {
				// An earlier run recorded this exception and stopped before its
				// gate: the run files the gate and leaves the record as it is.
				delete(want, "pr_state")
			}
			meta(t, b, want)
			if b.Status != "blocked" || readsPR(d.github) {
				t.Fatalf("an invalid record left the bead %s, or read GitHub %v", b.Status, d.github.Reads())
			}
			if g := d.gates.list(); !slices.Equal(g, []string{bead + " " + record.Invalid}) {
				t.Fatalf("gates filed %v", g)
			}
		})
	}
}

func TestAnOpenChangedHeadIsRequeuedForValidation(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	is(t, d.once(t), pr.ActRequeued)
	b := d.row(t)
	if b.Status != "open" || b.Assignee != refinery {
		t.Fatalf("a changed head left the bead %s under %s", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": other, "pr_head_sha": head,
		"existing_pr": prURL, "pr_reconcile_pending": "<absent>", "blocked_reason": "<absent>"})
	if !strings.Contains(b.Metadata["rejection_reason"], other) {
		t.Fatalf("the requeue's reason %q does not name the head found", b.Metadata["rejection_reason"])
	}
}

func TestAClosedUnmergedPRStaysBlockedBehindAGate(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	meta(t, b, map[string]string{"merge_result": record.ClosedUnmerged, "pr_state": "closed_unmerged", "pr_reconcile_pending": "<absent>"})
	if b.Status != "blocked" || !slices.Equal(d.gates.list(), []string{bead + " " + record.ClosedUnmerged}) {
		t.Fatalf("a closed PR left the bead %s with gates %v", b.Status, d.gates.list())
	}
}

func mergedOnGitHub(d *land, h string) {
	d.pr.Facts.State, d.pr.Facts.HeadRefOid = "MERGED", h
	d.pr.Facts.MergeCommit, d.pr.Facts.MergedAt = merged, "2026-11-12T08:30:00Z"
}

// The exception is recorded, guarded, before its gate is filed. A gate that
// does not file keeps the marker, and the next run files it and clears it.
func TestAnExceptionWhoseGateDidNotFileIsFiledByTheNextRun(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	d.gates.err = errors.New("human-gate: could not read the bead's gates")
	is(t, d.once(t), pr.ActRetry)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("the exception left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.ClosedUnmerged, "pr_reconcile_pending": "true"})
	d.gates.err = nil
	is(t, d.once(t), pr.ActExcepted)
	meta(t, d.row(t), map[string]string{"merge_result": record.ClosedUnmerged, "pr_reconcile_pending": "<absent>"})
	if !slices.Equal(d.gates.list(), []string{bead + " " + record.ClosedUnmerged}) {
		t.Fatalf("gates filed %v", d.gates.list())
	}
	if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
		t.Fatalf("a later run read the excepted bead: %+v", out)
	}
}

// An exception on a bead that a release took between the run's read and its
// write records nothing and files no gate.
func TestAnExceptionOnABeadThatMovedFilesNoGate(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	once := false
	d.store.BeforeUpdate = func(string, []string) error {
		if !once {
			once = true
			d.put("open", "")
		}
		return nil
	}
	is(t, d.once(t), pr.ActMoved)
	if len(d.gates.list()) != 0 || d.row(t).Metadata["merge_result"] != record.Pending {
		t.Fatalf("a moved bead got gates %v and result %s", d.gates.list(), d.row(t).Metadata["merge_result"])
	}
}

func TestAMergedValidatedHeadOnItsTargetCloses(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	is(t, d.once(t), pr.ActLanded)
	b := d.row(t)
	if b.Status != "closed" {
		t.Fatalf("a verified merge left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.Merged, "merged_sha": merged, "merged_target": "main",
		"pr_state": "merged", "pr_merged_at": "2026-11-12T08:30:00Z", "pr_head_sha": head, "branch": branch,
		"pr_reconcile_pending": "<absent>", "blocked_reason": "<absent>"})
	if !strings.Contains(b.Notes, "merged to main at "+merged[:8]) {
		t.Fatalf("the close names no merge: %q", b.Notes)
	}
	// The marker is gone, so no later run reads the bead again.
	if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
		t.Fatalf("a later run read a landed bead: %+v", out)
	}
}

func TestAMergedChangedHeadStaysBlockedBehindAGate(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, other)
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	meta(t, b, map[string]string{"merge_result": record.MergedUnvalidatedHead, "pr_reconcile_pending": "<absent>"})
	if b.Status != "blocked" || !slices.Equal(d.gates.list(), []string{bead + " " + record.MergedUnvalidatedHead}) {
		t.Fatalf("a merge of another head left the bead %s with gates %v", b.Status, d.gates.list())
	}
}

func TestAVerifiedMergeWhoseCloseIsRefusedRemainsRetryable(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	refuse := true
	d.store.BeforeUpdate = func(_ string, args []string) error {
		if refuse && slices.Contains(args, "--status=closed") {
			return errors.New("cannot close blocked issue: a live blocker")
		}
		return nil
	}
	is(t, d.once(t), pr.ActRetry)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("a refused close left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.Pending, "pr_reconcile_pending": "true", "pr_state": "open"})
	refuse = false
	is(t, d.once(t), pr.ActLanded)
}

func TestAnUnreachableMergeCommitRetriesWithoutClose(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.co.reachable = map[string]bool{}
	is(t, d.once(t), pr.ActRetry)
	b := d.row(t)
	meta(t, b, map[string]string{"pr_state": "merge_unreachable", "pr_reconcile_pending": "true", "merge_result": record.Pending})
	if b.Status != "blocked" || len(d.gates.list()) != 0 {
		t.Fatalf("an unreachable merge left the bead %s with gates %v", b.Status, d.gates.list())
	}
}

func TestAFailedFetchOrLookupIsRetried(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.co.fetchErr = errors.New("could not read from remote repository")
	is(t, d.once(t), pr.ActRetry)
	meta(t, d.row(t), map[string]string{"pr_state": "merged_unverified", "pr_reconcile_pending": "true"})

	d = newLand(t)
	d.github.Fail["PullRequest"] = errors.New("HTTP 502")
	is(t, d.once(t), pr.ActRetry)
	meta(t, d.row(t), map[string]string{"pr_state": "lookup_failed", "pr_reconcile_pending": "true"})
}

func TestAClosedBeadWithNoVerifiedMergeIsReopenedBlocked(t *testing.T) {
	d := newLand(t)
	d.put("closed", refinery)
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("a closed bead with no verified merge was left %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.LegacyClosed, "pr_reconcile_pending": "<absent>"})
	if !slices.Equal(d.gates.list(), []string{bead + " " + record.LegacyClosed}) {
		t.Fatalf("gates filed %v", d.gates.list())
	}
}

func TestAClosedBeadOnAVerifiedMergeHasItsMarkerCleared(t *testing.T) {
	d := newLand(t)
	for k, v := range map[string]string{"merge_result": record.Merged, "merged_sha": merged, "pr_state": "merged",
		"pr_merged_at": "2026-11-12T08:30:00Z"} {
		d.md[k] = v
	}
	d.put("closed", refinery)
	is(t, d.once(t), pr.ActSettled)
	if b := d.row(t); b.Status != "closed" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the settle left %s with marker %q", b.Status, b.Metadata["pr_reconcile_pending"])
	}
}

func TestAPRThatIsNoLongerTheRecordsIsAnException(t *testing.T) {
	for name, change := range map[string]func(*ghfake.PR){
		"its head branch": func(p *ghfake.PR) { p.Facts.HeadRefName = "polecat/other" },
		"its base":        func(p *ghfake.PR) { p.Facts.BaseRefName = "release" },
		"its URL":         func(p *ghfake.PR) { p.Facts.URL = "https://github.com/acme/widgets/pull/8" },
	} {
		t.Run(name, func(t *testing.T) {
			d := newLand(t)
			change(d.pr)
			is(t, d.once(t), pr.ActExcepted)
			meta(t, d.row(t), map[string]string{"merge_result": record.Invalid})
		})
	}
}

func TestTheOldestPendingRecordIsReadFirst(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	for i, at := range []string{"2026-11-12T05:00:00Z", "2026-11-12T03:00:00Z", "", "2026-11-12T04:00:00Z"} {
		md := map[string]string{}
		for k, v := range d.md {
			md[k] = v
		}
		md["pr_last_checked_at"] = at
		d.store.Put(fake.Bead{ID: fmt.Sprintf("tk-o%d", i), Status: "blocked", Assignee: refinery, Metadata: md})
	}
	out := d.reconcile(t, pr.Options{Count: 2})
	if len(out) != 2 || out[0].Bead != "tk-o2" || out[1].Bead != "tk-1" {
		t.Fatalf("the run read %+v, want the never-checked tk-o2, then tk-1 checked at 01:00", out)
	}
}

// A record reads its PR once, and the evaluator takes that read and the run's
// login rather than asking GitHub again for either.
func TestARunReadsEachRecordsPROnceAndTheLoginOncePerHost(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	for i := 0; i < 2; i++ {
		md := map[string]string{}
		for k, v := range d.md {
			md[k] = v
		}
		d.store.Put(fake.Bead{ID: fmt.Sprintf("tk-r%d", i), Status: "blocked", Assignee: refinery, Metadata: md})
	}
	out := d.reconcile(t, pr.Options{Count: 10})
	if len(out) != 3 {
		t.Fatalf("three records, %d outcomes: %+v", len(out), out)
	}
	for _, o := range out {
		is(t, o, pr.ActChecked)
	}
	count := func(method string) int {
		n := 0
		for _, r := range d.github.Reads() {
			if r == method {
				n++
			}
		}
		return n
	}
	if n := count("PullRequest"); n != 3 {
		t.Errorf("the run read the PR %d times for three records, want 3: %v", n, d.github.Reads())
	}
	if n := count("Login"); n != 1 {
		t.Errorf("the run read the login %d times, want once: %v", n, d.github.Reads())
	}
}

// --- the pack's merge request -------------------------------------------------

func TestAReadyPRIsMergedWithItsHeadPinned(t *testing.T) {
	d := newLand(t)
	is(t, d.once(t), pr.ActRequested)
	if got := asks(d.github); !slices.Equal(got, []string{"MergePullRequest PR_7 " + head}) {
		t.Fatalf("asked %v, want one merge pinned to %s", got, head)
	}
	if d.row(t).Status != "blocked" {
		t.Fatal("the request closed the bead before the merge was verified")
	}
	// The next run reads the merged PR by its number and closes the bead.
	is(t, d.once(t), pr.ActLanded)
	if d.row(t).Status != "closed" || len(d.github.Asks()) != 1 {
		t.Fatalf("after the merge the bead is %s, with asks %v", d.row(t).Status, asks(d.github))
	}
}

func TestAPushBetweenTheAnswerAndTheRequestIsRefusedAndRequeued(t *testing.T) {
	d := newLand(t)
	d.github.OnMerge = func(_ string, p *ghfake.PR, h string) error {
		p.Facts.HeadRefOid = other
		if p.Facts.HeadRefOid != h {
			return errors.New("github: Head branch was modified. Review and try the merge again.")
		}
		return nil
	}
	is(t, d.once(t), pr.ActRetry)
	if d.pr.Facts.State != "OPEN" || d.row(t).Status != "blocked" {
		t.Fatal("a refused request merged or moved the bead")
	}
	is(t, d.once(t), pr.ActRequeued)
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": other})
}

func TestARequestLeftUnansweredIsReadAgain(t *testing.T) {
	// GitHub takes the request after its answer was lost: the next run finds it
	// merged.
	d := newLand(t)
	d.github.OnMerge = func(_ string, p *ghfake.PR, h string) error {
		p.Facts.State, p.Facts.MergeCommit, p.Facts.MergedAt = "MERGED", merged, "2026-11-12T08:30:00Z"
		return errors.New("github: timeout awaiting response")
	}
	is(t, d.once(t), pr.ActRetry)
	is(t, d.once(t), pr.ActLanded)

	// GitHub never took it: the next run decides again and asks again.
	d = newLand(t)
	d.github.OnMerge = func(string, *ghfake.PR, string) error { return errors.New("github: timeout awaiting response") }
	is(t, d.once(t), pr.ActRetry)
	is(t, d.once(t), pr.ActRetry)
	if len(d.github.Asks()) != 2 {
		t.Fatalf("an unanswered request was not asked again: %v", asks(d.github))
	}
}

func TestAMergeQueueTakesThePROrDropsIt(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.MergeQueueEnabled = true
	is(t, d.once(t), pr.ActRequested)
	if got := asks(d.github); !slices.Equal(got, []string{"EnqueuePullRequest PR_7 " + head}) {
		t.Fatalf("asked %v, want one enqueue pinned to %s", got, head)
	}
	// In the queue, the PR's merge is requested already.
	is(t, d.once(t), pr.ActChecked)
	if len(d.github.Asks()) != 1 {
		t.Fatalf("a queued PR was asked again: %v", asks(d.github))
	}
	// The queue drops it: the next run decides again.
	d.pr.Facts.InMergeQueue = false
	is(t, d.once(t), pr.ActRequested)
	// The queue takes it: the run after closes the bead.
	mergedOnGitHub(d, head)
	is(t, d.once(t), pr.ActLanded)
}

func TestAPRMergedIntoAnotherBaseIsNotLanded(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.pr.Facts.BaseRefName = "release"
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	if b.Status != "blocked" || b.Metadata["merge_result"] != record.Invalid {
		t.Fatalf("a merge into another base left the bead %s, %s", b.Status, b.Metadata["merge_result"])
	}
}

// --- the record's writers under the lock --------------------------------------

// pause makes the first read of the PR a run makes wait until the test lets it
// go, and reports when the run is there, holding the lock.
func pause(g *ghfake.GitHub) (there, goOn chan struct{}) {
	there, goOn = make(chan struct{}), make(chan struct{})
	var once sync.Once
	g.OnRead = func(method string, _ *ghfake.PR) {
		if method != "PullRequest" {
			return
		}
		once.Do(func() {
			close(there)
			<-goOn
		})
	}
	return there, goOn
}

// waits fails unless done stays open for a while: the writer behind it waits.
func waits(t *testing.T, done chan error, who string) {
	t.Helper()
	select {
	case err := <-done:
		t.Fatalf("%s went ahead while another writer held the lock: %v", who, err)
	case <-time.After(300 * time.Millisecond):
	}
}

// dispose is a disposition's close as bead-rehome.sh makes it: under the
// record lock, it reads the bead, then closes it guarded on what it read and
// clears any marker it finds, in one write.
func dispose(d *land) error {
	release, err := record.Lock(d.l.Dir, 5*time.Second)
	if err != nil {
		return err
	}
	defer release()
	b, _ := d.store.Row(bead)
	args := []string{"--if-status=" + b.Status, "--if-assignee=" + b.Assignee, "--status=closed"}
	if _, marked := b.Metadata["pr_reconcile_pending"]; marked {
		args = append(args, "--unset-metadata", "pr_reconcile_pending")
	}
	_, err = d.store.Update(bead, args...)
	return err
}

func TestARecordWriteWaitsWhileARunHoldsTheLockAndLandsAfterItsLastWrite(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	there, goOn := pause(d.github)
	ran := make(chan error, 1)
	go func() { ran <- d.l.Reconcile(pr.Options{Count: 10}, func(pr.RunOutcome) {}) }()
	<-there
	recorded := make(chan error, 1)
	go func() { recorded <- d.l.Record(bead, publication(other)) }()
	waits(t, recorded, "the publication")
	close(goOn)
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	ws := d.store.Writes()
	if len(ws) != 3 || !slices.Contains(ws[0].Args, "pr_state=open") || !slices.Contains(ws[2].Args, "pr_head_sha="+other) {
		t.Fatalf("the writes landed out of order: %+v", ws)
	}
	meta(t, d.row(t), map[string]string{"pr_head_sha": other, "merge_result": record.Pending})
}

func TestARunWaitsWhileARecordWriteHoldsTheLockThenReadsTheWholeRecord(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	d.pr.Facts.HeadRefOid = other // the refinery validated a new head and pushed it
	between, goOn := make(chan struct{}), make(chan struct{})
	n := 0
	d.store.BeforeUpdate = func(string, []string) error {
		if n++; n == 2 {
			close(between)
			<-goOn
		}
		return nil
	}
	recorded := make(chan error, 1)
	go func() { recorded <- d.l.Record(bead, publication(other)) }()
	<-between
	ran := make(chan error, 1)
	var out []pr.RunOutcome
	go func() { ran <- d.l.Reconcile(pr.Options{Count: 10}, func(o pr.RunOutcome) { out = append(out, o) }) }()
	waits(t, ran, "the run")
	close(goOn)
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if len(out) != 1 || out[0].Action != pr.ActChecked {
		t.Fatalf("the run read %+v, want the whole record at the new head, checked and not requeued", out)
	}
}

func TestADispositionsCloseWaitsWhileARunHoldsTheLockAndClearsTheMarker(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	there, goOn := pause(d.github)
	ran := make(chan error, 1)
	go func() { ran <- d.l.Reconcile(pr.Options{Count: 10}, func(pr.RunOutcome) {}) }()
	<-there
	disposed := make(chan error, 1)
	go func() { disposed <- dispose(d) }()
	waits(t, disposed, "the disposition")
	close(goOn)
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if err := <-disposed; err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
			t.Fatalf("a later run read the disposed bead: %+v", out)
		}
	}
	if b := d.row(t); b.Status != "closed" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the disposed bead is %s with marker %q", b.Status, b.Metadata["pr_reconcile_pending"])
	}
}

func TestADispositionThatClosesBeforeAPublicationTakesTheLockLeavesNoRecord(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch}
	d.put("open", refinery)
	if err := dispose(d); err != nil {
		t.Fatal(err)
	}
	err := d.l.Record(bead, publication(head))
	var refused *pr.Refusal
	if !errors.As(err, &refused) || refused.Armed {
		t.Fatalf("a publication on a disposed bead read as %v", err)
	}
	for i := 0; i < 2; i++ {
		if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
			t.Fatalf("a later run read the disposed bead: %+v", out)
		}
	}
	b := d.row(t)
	if b.Status != "closed" || len(b.Metadata) != 1 {
		t.Fatalf("the disposed bead is %s carrying %v", b.Status, b.Metadata)
	}
}

func TestACloseOrAReleaseBetweenThePublicationsReadAndItsFirstWriteIsRefused(t *testing.T) {
	for name, move := range map[string]func(*fake.Bead){
		"a close":                func(b *fake.Bead) { b.Status = "closed" },
		"a stand-down's release": func(b *fake.Bead) { b.Assignee = "" },
	} {
		t.Run(name, func(t *testing.T) {
			d := newLand(t)
			d.md = map[string]string{"branch": branch}
			d.put("open", refinery)
			once := false
			d.store.BeforeUpdate = func(string, []string) error {
				if !once {
					once = true
					b, _ := d.store.Row(bead)
					move(&b)
					d.store.Put(b)
				}
				return nil
			}
			var refused *pr.Refusal
			if err := d.l.Record(bead, publication(head)); !errors.As(err, &refused) || refused.Armed {
				t.Fatalf("the publication read as %v", err)
			}
			if b := d.row(t); b.Metadata["pr_reconcile_pending"] != "" || b.Metadata["merge_result"] != "" {
				t.Fatalf("the guard let a write through: %v", b.Metadata)
			}
			if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
				t.Fatalf("a later run read the bead: %+v", out)
			}
		})
	}
}

func TestADispositionThatStartsBeforeAPublicationMarksTheBeadWaitsThenClearsTheMarker(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch}
	d.put("open", refinery)
	between, goOn := make(chan struct{}), make(chan struct{})
	n := 0
	d.store.BeforeUpdate = func(string, []string) error {
		if n++; n == 1 {
			close(between)
			<-goOn
		}
		return nil
	}
	recorded := make(chan error, 1)
	go func() { recorded <- d.l.Record(bead, publication(head)) }()
	<-between
	disposed := make(chan error, 1)
	go func() { disposed <- dispose(d) }()
	waits(t, disposed, "the disposition")
	close(goOn)
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	if err := <-disposed; err != nil {
		t.Fatal(err)
	}
	b := d.row(t)
	if b.Status != "closed" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the disposition left %s with marker %q", b.Status, b.Metadata["pr_reconcile_pending"])
	}
	if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
		t.Fatalf("a later run read the disposed bead: %+v", out)
	}
}

func TestAReleaseAfterTheRecordLeavesTheBeadReleased(t *testing.T) {
	check := func(t *testing.T, d *land) {
		t.Helper()
		b := d.row(t)
		if b.Status != "open" || b.Assignee != "" {
			t.Fatalf("the released bead is %s under %q", b.Status, b.Assignee)
		}
		if b.Metadata["pr_reconcile_pending"] != "" || !strings.Contains(b.Notes, prURL) {
			t.Fatalf("the marker %q stands, or the note %q names no PR", b.Metadata["pr_reconcile_pending"], b.Notes)
		}
		meta(t, b, map[string]string{"merge_result": record.Pending, "pr_head_sha": head})
		for i := 0; i < 2; i++ {
			if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
				t.Fatalf("a later run read the released bead: %+v", out)
			}
		}
		if len(d.github.Asks()) != 0 {
			t.Fatalf("a released bead's PR was asked to merge: %v", asks(d.github))
		}
	}
	t.Run("after its record", func(t *testing.T) {
		d := newLand(t)
		d.put("open", "")
		is(t, d.once(t), pr.ActReleased)
		check(t, d)
	})
	t.Run("while a run reads GitHub", func(t *testing.T) {
		d := newLand(t)
		d.github.OnRead = func(method string, _ *ghfake.PR) {
			if method == "PullRequest" {
				if b, _ := d.store.Row(bead); b.Assignee != "" {
					d.put("open", "")
				}
			}
		}
		is(t, d.once(t), pr.ActMoved)
		d.github.OnRead = nil
		is(t, d.once(t), pr.ActReleased)
		check(t, d)
	})
}

func TestASecondRunActsOnARecordOnlyOnceTheFirstHasWrittenIt(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	there, goOn := pause(d.github)
	first, second := make(chan error, 1), make(chan error, 1)
	var firstOut, secondOut []pr.RunOutcome
	go func() {
		first <- d.l.Reconcile(pr.Options{Count: 10}, func(o pr.RunOutcome) { firstOut = append(firstOut, o) })
	}()
	<-there
	// The watchdog closed the first run's tracking bead, and the next cooldown
	// started a second run while the first still holds the record.
	go func() {
		second <- d.l.Reconcile(pr.Options{Count: 10}, func(o pr.RunOutcome) { secondOut = append(secondOut, o) })
	}()
	waits(t, second, "the second run")
	close(goOn)
	if err := <-first; err != nil {
		t.Fatal(err)
	}
	if err := <-second; err != nil {
		t.Fatal(err)
	}
	if len(firstOut) != 1 || firstOut[0].Action != pr.ActRequeued {
		t.Fatalf("the first run did %+v", firstOut)
	}
	if len(secondOut) != 1 || secondOut[0].Action != pr.ActSkipped {
		t.Fatalf("the second run did %+v, want it to read the record as the first left it, with no marker", secondOut)
	}
	if n := len(d.store.Writes()); n != 1 {
		t.Fatalf("%d writes, want the first run's one", n)
	}
}

// A run that read a half-written bead, before the refinery requeued it to the
// pool, writes nothing. The next run clears its marker, names the PR in a note
// and leaves it with the pool.
func TestARunThatReadAHalfWrittenBeadBeforeItsRequeueToThePoolWritesNothing(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch, "pr_reconcile_pending": "true", "existing_pr": prURL}
	d.put("open", refinery)
	once := false
	d.store.BeforeUpdate = func(string, []string) error {
		if !once {
			once = true
			d.put("open", "") // the refinery's requeue through gc sling unassigns it
		}
		return nil
	}
	is(t, d.once(t), pr.ActMoved)
	b := d.row(t)
	if b.Metadata["merge_result"] != "" || b.Metadata["pr_reconcile_pending"] != "true" {
		t.Fatalf("the refused write landed: %v", b.Metadata)
	}
	is(t, d.once(t), pr.ActReleased)
	b = d.row(t)
	if b.Status != "open" || b.Assignee != "" || b.Metadata["pr_reconcile_pending"] != "" || !strings.Contains(b.Notes, prURL) {
		t.Fatalf("the requeued bead is %s under %q carrying %v, notes %q", b.Status, b.Assignee, b.Metadata, b.Notes)
	}
}

func TestARunStoppedAtItsDeadlineLeavesItsUnreadRecordsToTheNextRun(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	for _, id := range []string{"tk-a", "tk-b"} {
		md := map[string]string{}
		for k, v := range d.md {
			md[k] = v
		}
		md["pr_last_checked_at"] = "2026-11-12T02:00:00Z"
		d.store.Put(fake.Bead{ID: id, Status: "blocked", Assignee: refinery, Metadata: md})
	}
	deadline := time.Now().Add(200 * time.Millisecond)
	d.github.OnRead = func(method string, _ *ghfake.PR) {
		if method == "PullRequest" {
			time.Sleep(time.Until(deadline) + 50*time.Millisecond)
		}
	}
	out := d.reconcile(t, pr.Options{Count: 10, Deadline: deadline})
	if len(out) != 2 || out[0].Bead != bead || out[1].Action != pr.ActSkipped {
		t.Fatalf("the run did %+v, want the oldest read and the rest left at the deadline", out)
	}
	d.github.OnRead = nil
	next := d.reconcile(t, pr.Options{Count: 1})
	if len(next) != 1 || next[0].Bead != "tk-a" {
		t.Fatalf("the next run read %+v, want the unread tk-a first", next)
	}
}

func TestTheOrderOfRecordsAcrossRunsUnderLoad(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	tick := time.Date(2026, 11, 12, 9, 0, 0, 0, time.UTC)
	d.l.Now = func() time.Time { tick = tick.Add(time.Second); return tick }
	var ids []string
	for i := 0; i < 50; i++ {
		id := fmt.Sprintf("tk-l%02d", i)
		md := map[string]string{}
		for k, v := range d.md {
			md[k] = v
		}
		md["pr_last_checked_at"] = fmt.Sprintf("2026-11-12T0%d:%02d:00Z", i%5, i)
		d.store.Put(fake.Bead{ID: id, Status: "blocked", Assignee: refinery, Metadata: md})
		ids = append(ids, id)
	}
	ids = append(ids, bead)
	seen := map[string]int{}
	for run := 0; run < 3; run++ {
		for _, o := range d.reconcile(t, pr.Options{Count: 17}) {
			seen[o.Bead]++
		}
	}
	for _, id := range ids {
		if seen[id] != 1 {
			t.Fatalf("%s was read %d times in three runs over 51 records, want once each: %v", id, seen[id], seen)
		}
	}
	// A record published between runs is read in the next run, ahead of the
	// rest.
	md := map[string]string{}
	for k, v := range d.md {
		md[k] = v
	}
	delete(md, "pr_last_checked_at")
	d.store.Put(fake.Bead{ID: "tk-new", Status: "blocked", Assignee: refinery, Metadata: md})
	if out := d.reconcile(t, pr.Options{Count: 17}); out[0].Bead != "tk-new" {
		t.Fatalf("the new record waited behind %s", out[0].Bead)
	}
}

// --- the lock ---------------------------------------------------------------

func TestTheLockWaitsForItsHolderAndGivesUpAtItsBound(t *testing.T) {
	dir := t.TempDir()
	release, err := record.Lock(dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := record.Lock(dir, 100*time.Millisecond); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("a second writer got the lock or failed otherwise: %v", err)
	}
	got := make(chan error, 1)
	go func() {
		r, err := record.Lock(dir, 5*time.Second)
		if err == nil {
			r()
		}
		got <- err
	}()
	time.Sleep(100 * time.Millisecond)
	release()
	if err := <-got; err != nil {
		t.Fatalf("the waiting writer did not get the lock once it was free: %v", err)
	}
}

// A run that an order's time limit stops holds nothing: the kernel frees the
// lock when the run's process ends.
func TestARunStoppedAtItsTimeLimitLeavesTheLockFree(t *testing.T) {
	if dir := os.Getenv("GCTK_TEST_HOLD_RECORD_LOCK"); dir != "" {
		if _, err := record.Lock(dir, time.Second); err != nil {
			os.Exit(3)
		}
		fmt.Println("held")
		time.Sleep(time.Minute)
		os.Exit(0)
	}
	dir := t.TempDir()
	cmd := exec.Command(os.Args[0], "-test.run", "^TestARunStoppedAtItsTimeLimitLeavesTheLockFree$")
	cmd.Env = append(os.Environ(), "GCTK_TEST_HOLD_RECORD_LOCK="+dir)
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 4)
	if _, err := out.Read(buf); err != nil || string(buf) != "held" {
		t.Fatalf("the holder did not take the lock: %q %v", buf, err)
	}
	if _, err := record.Lock(dir, 100*time.Millisecond); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("the lock was free while its holder ran: %v", err)
	}
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
	release, err := record.Lock(dir, 2*time.Second)
	if err != nil {
		t.Fatalf("the lock stayed held after its holder was stopped: %v", err)
	}
	release()
}

// bead-rehome.sh takes the same lock with flock(1), so the shell's lock and the
// verbs' exclude each other.
func TestTheShellsFlockAndTheRecordLockExcludeEachOther(t *testing.T) {
	flock, err := exec.LookPath("flock")
	if err != nil {
		t.Skip("flock(1) is not on PATH")
	}
	dir := t.TempDir()
	release, err := record.Lock(dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	path := dir + "/" + record.LockFile
	if exec.Command(flock, "-n", path, "true").Run() == nil {
		t.Fatal("flock(1) took the lock while gctk held it")
	}
	release()
	if err := exec.Command(flock, "-n", path, "true").Run(); err != nil {
		t.Fatalf("flock(1) did not take the free lock: %v", err)
	}
	hold := exec.Command(flock, path, "sleep", "2")
	if err := hold.Start(); err != nil {
		t.Fatal(err)
	}
	defer hold.Wait()
	time.Sleep(300 * time.Millisecond)
	if _, err := record.Lock(dir, 100*time.Millisecond); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("gctk took the lock while flock(1) held it: %v", err)
	}
}
