package pr_test

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The labels' cases (specs/tk-1tfzr71.149/design.md, section 9). The landing
// order compares the labels the one-PR update saved with the ones the store
// derives, and has the writer write only where they differ. The net clears the
// city's labels off the PRs no live bead owns. Each starts from the watched
// world, whose PR the cheap question has read, with its bead on the old path
// so the run owes the record no act and every outcome is a label's.

// labelWriter is the labels' writer as a test sets it: the labels the store
// derives for each bead, a derivation that fails, writes that fail while fail
// counts down, and writes that wait until they are stopped. A write it makes
// edits the PR's labels on GitHub as the writer does, so the PR watch's next
// pass saves what it wrote.
type labelWriter struct {
	mu        sync.Mutex
	github    *ghfake.GitHub
	derived   map[string][]string
	deriveErr error
	fail      int
	block     bool
	derives   [][]string
	writes    []string
}

func ours(name string) bool {
	return strings.HasPrefix(name, "status: ") || strings.HasPrefix(name, "held: ")
}

func (l *labelWriter) Derive(_ *ledger.Ledger, beads []string) (map[string][]string, map[string]error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.derives = append(l.derives, slices.Clone(beads))
	out, failed := map[string][]string{}, map[string]error{}
	for _, b := range beads {
		if l.deriveErr != nil {
			failed[b] = l.deriveErr
			continue
		}
		out[b] = l.derived[b]
	}
	return out, failed
}

func (*labelWriter) Kept(name string) bool { return ours(name) }

func (*labelWriter) Names() []string {
	return []string{"status: working", "status: merging", "status: needs-review", "held: gate"}
}

func (l *labelWriter) Reconcile(ctx context.Context, bead, host, repo string, number int, current []string) error {
	return l.write(ctx, fmt.Sprintf("reconcile %s %s/%s#%d [%s]", bead, host, repo, number, strings.Join(current, ",")),
		repo, number, l.wanted(bead))
}

func (l *labelWriter) Clear(ctx context.Context, host, repo string, number int, current []string) error {
	return l.write(ctx, fmt.Sprintf("clear %s/%s#%d [%s]", host, repo, number, strings.Join(current, ",")),
		repo, number, nil)
}

func (l *labelWriter) wanted(bead string) []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.derived[bead]
}

func (l *labelWriter) write(ctx context.Context, call, repo string, number int, want []string) error {
	l.mu.Lock()
	l.writes = append(l.writes, call)
	fail := l.fail > 0
	if fail {
		l.fail--
	}
	block := l.block
	l.mu.Unlock()
	if block {
		<-ctx.Done()
		return fmt.Errorf("pr-status-label.sh was stopped: %w", ctx.Err())
	}
	if fail {
		return errors.New("pr-status-label.sh: exit 2: could not write the PR's labels")
	}
	p := l.github.PRs[strings.ToLower(repo)+fmt.Sprintf("#%d", number)]
	if p == nil {
		return fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	labels := slices.DeleteFunc(slices.Clone(p.Labels), ours)
	p.Labels = append(labels, want...)
	return nil
}

func (l *labelWriter) made() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return slices.Clone(l.writes)
}

// labeled is the watched world with its bead on the old path, the labels'
// writer, and a landing order that keeps the labels, once a pass of the cheap
// question has saved the PR's read.
type labeled struct {
	*watched
	lw *labelWriter
	l  pr.Landing
}

func newLabeled(t *testing.T, shows []string) *labeled {
	t.Helper()
	d := newWatched(t)
	d.pr.Labels = shows
	md := maps.Clone(d.md)
	md["merge_result"] = "pull_request"
	d.store.Put(fake.Bead{ID: bead, Title: "the work", Status: "open", Metadata: md})
	lw := &labelWriter{github: d.github, derived: map[string][]string{bead: {"status: merging"}}}
	d.w.Labels, d.w.Origin = lw, func() (string, error) { return origin, nil }
	x := &labeled{watched: d, lw: lw, l: pr.Landing{
		Ledger:   ledger.New(d.store),
		Dir:      d.w.Dir,
		Refinery: refinery,
		Hub:      func(context.Context, string) pr.Hub { return d.github },
		Feedback: func() (pr.Feedback, error) { return d.rule, nil },
		Checkout: &checkout{origin: origin},
		Gates:    &gates{},
		Labels:   lw,
		Now:      func() time.Time { return time.Date(2026, 11, 16, 11, 0, 0, 0, time.UTC) },
		Wait:     5 * time.Second,
		Shuffle:  func([]string) {},
	}}
	if rep := d.poll(t); len(rep.Failed) != 0 {
		t.Fatalf("the first pass failed %v", rep.Failed)
	}
	return x
}

// run runs the landing order once and returns its outcomes, failing unless it
// returns an error exactly when an act did not complete. It fails too if the
// run wrote the store, or read GitHub other than one read of a PR for each
// outcome, since a label write writes nothing on the bead and reads only the
// PR, which its writer reads the labels of itself.
func (d *labeled) run(t *testing.T, o pr.Options) []pr.RunOutcome {
	t.Helper()
	reads, writes := len(d.github.Reads()), len(d.store.Writes())
	var out []pr.RunOutcome
	err := d.l.Reconcile(o, func(x pr.RunOutcome) { out = append(out, x) })
	owed := slices.ContainsFunc(out, func(x pr.RunOutcome) bool { return x.Action == pr.ActRetry || x.Action == pr.ActFailed })
	if (err != nil) != owed {
		t.Fatalf("Reconcile returned %v over the outcomes %+v", err, out)
	}
	if got := d.github.Reads()[reads:]; len(got) > len(out) || slices.ContainsFunc(got, func(r string) bool { return r != "PullRequest" }) {
		t.Fatalf("the run read GitHub %v over the outcomes %+v", got, out)
	}
	if got := d.store.Writes()[writes:]; len(got) != 0 {
		t.Fatalf("the run wrote the store: %+v", got)
	}
	return out
}

// one fails unless the run had one outcome, of action, for the bead, and
// returns it.
func one(t *testing.T, out []pr.RunOutcome, action string) pr.RunOutcome {
	t.Helper()
	if len(out) != 1 || out[0].Action != action || out[0].Bead != bead {
		t.Fatalf("the run's outcomes %+v, want one %s for %s", out, action, bead)
	}
	return out[0]
}

// The landing order writes the labels the store derives where the ones the PR
// shows differ: it adds a derived label the PR lacks, and takes off a label of
// the writer's that the store no longer derives, leaving every other label.
// It reads the PR's state itself and hands the writer no labels, so the writer
// reads them itself. Once the PR watch saves what the writer wrote, the next
// run finds nothing to write.
func TestTheLandingOrderWritesTheLabelsTheStoreDerives(t *testing.T) {
	for _, tc := range []struct {
		name          string
		shows, derive []string
		write         string
		after         []string
	}{
		{"a derived label added", nil, []string{"status: needs-review"},
			"reconcile tk-1 github.com/acme/widgets#7 []", []string{"status: needs-review"}},
		{"a stale label taken off", []string{"bug", "held: gate", "status: working"}, []string{"status: working"},
			"reconcile tk-1 github.com/acme/widgets#7 []", []string{"bug", "status: working"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := newLabeled(t, tc.shows)
			d.lw.derived[bead] = tc.derive
			o := one(t, d.run(t, pr.Options{}), pr.ActLabeled)
			if !strings.Contains(o.Detail, "where the store derives "+strings.Join(tc.derive, ", ")) {
				t.Errorf("the outcome says %q", o.Detail)
			}
			if got := d.lw.made(); !slices.Equal(got, []string{tc.write}) {
				t.Fatalf("the writer was asked %q, want %q", got, tc.write)
			}
			if got := slices.Sorted(slices.Values(d.pr.Labels)); !slices.Equal(got, tc.after) {
				t.Fatalf("the PR shows %q, want %q", got, tc.after)
			}
			updated(t, d.poll(t), "labels")
			if out := d.run(t, pr.Options{}); len(out) != 0 || len(d.lw.made()) != 1 {
				t.Fatalf("the next run reported %+v and wrote %q", out, d.lw.made())
			}
		})
	}
}

// Labels the PR shows that equal the ones the store derives, other labels
// aside, owe no write, and the run reports nothing of them.
func TestLabelsThatEqualTheDerivedOnesOweNoWrite(t *testing.T) {
	d := newLabeled(t, []string{"held: gate", "bug", "status: needs-attention"})
	d.lw.derived[bead] = []string{"status: needs-attention", "held: gate"}
	if out := d.run(t, pr.Options{}); len(out) != 0 || len(d.lw.made()) != 0 {
		t.Fatalf("the run reported %+v and wrote %q", out, d.lw.made())
	}
	if got := d.lw.derives; len(got) != 1 || !slices.Equal(got[0], []string{bead}) {
		t.Fatalf("the run derived %q, want the open PR's bead once", got)
	}
}

// A PR that merged or closed shows none of the writer's labels, whatever its
// bead's state, so the run clears them without deriving any, and leaves the
// labels that are not the writer's.
func TestTheLandingOrderClearsAPRThatMergedOrClosed(t *testing.T) {
	for _, state := range []string{"MERGED", "CLOSED"} {
		t.Run(state, func(t *testing.T) {
			d := newLabeled(t, []string{"status: merging", "bug"})
			d.pr.Facts.State = state
			updated(t, d.poll(t), "pr")
			o := one(t, d.run(t, pr.Options{}), pr.ActLabeled)
			if want := "is " + strings.ToLower(state) + " and showed status: merging"; !strings.Contains(o.Detail, want) {
				t.Errorf("the outcome says %q, want it to say %q", o.Detail, want)
			}
			if got := d.lw.made(); !slices.Equal(got, []string{"clear github.com/acme/widgets#7 []"}) {
				t.Fatalf("the writer was asked %q", got)
			}
			if len(d.lw.derives) != 0 {
				t.Fatalf("the run derived %q for a PR that is %s", d.lw.derives, state)
			}
			if !slices.Equal(d.pr.Labels, []string{"bug"}) {
				t.Fatalf("the PR shows %q", d.pr.Labels)
			}
		})
	}
}

// The run writes a PR's labels on its own read of the PR: one the saved read
// gives closed that is open again has the labels the store derives written,
// not cleared.
func TestALabelWriteIsDecidedOnTheActsOwnReadOfThePR(t *testing.T) {
	d := newLabeled(t, []string{"status: merging", "bug"})
	d.pr.Facts.State = "CLOSED"
	updated(t, d.poll(t), "pr")
	d.pr.Facts.State = "OPEN"
	o := one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if !strings.Contains(o.Detail, "is open again") {
		t.Errorf("the outcome says %q", o.Detail)
	}
	if got := d.lw.made(); !slices.Equal(got, []string{"reconcile tk-1 github.com/acme/widgets#7 []"}) {
		t.Fatalf("the writer was asked %q, want the derived labels written", got)
	}
	if got := slices.Sorted(slices.Values(d.pr.Labels)); !slices.Equal(got, []string{"bug", "status: merging"}) {
		t.Fatalf("the PR shows %q", got)
	}
}

// A write that does not land records nothing on the bead: the run says so and
// exits as an act that did not complete, and the next run finds the same
// difference and makes the write.
func TestALabelWriteThatFailsIsMadeByTheNextRun(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.lw.fail = 1
	o := one(t, d.run(t, pr.Options{}), pr.ActRetry)
	if !strings.Contains(o.Detail, "nothing records it") || !strings.Contains(o.Detail, "could not write") {
		t.Errorf("the outcome says %q", o.Detail)
	}
	if before := d.row(t, bead).Metadata; slices.ContainsFunc(slices.Collect(maps.Keys(before)), func(k string) bool {
		return strings.Contains(k, "label")
	}) {
		t.Fatalf("the bead carries a label key after the failed write: %v", before)
	}
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if got := d.lw.made(); len(got) != 2 || got[0] != got[1] {
		t.Fatalf("the writer was asked %q, want the same write twice", got)
	}
	if !slices.Equal(d.pr.Labels, []string{"status: merging"}) {
		t.Fatalf("the PR shows %q", d.pr.Labels)
	}
}

// A label write is an act like the record's: it stops at the run's bound, and
// a run past its window starts none, leaving it to the next run.
func TestALabelWriteKeepsTheRunsBounds(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.lw.block = true
	o := one(t, d.run(t, pr.Options{Stop: 50 * time.Millisecond}), pr.ActRetry)
	if !strings.Contains(o.Detail, "stopped at its 50ms") {
		t.Errorf("the stopped write says %q", o.Detail)
	}
	d.lw.block = false
	now := time.Date(2026, 11, 16, 11, 0, 0, 0, time.UTC)
	d.l.Now = func() time.Time { now = now.Add(time.Minute); return now }
	o = one(t, d.run(t, pr.Options{Window: 45 * time.Second}), pr.ActLeft)
	if !strings.Contains(o.Detail, "compares the labels of "+prURL) || len(d.lw.made()) != 1 {
		t.Fatalf("the run past its window said %q and wrote %q", o.Detail, d.lw.made())
	}
}

// A derivation that does not read writes no label: the run says so and exits
// as an act that did not complete.
func TestALabelDerivationThatFailsWritesNothing(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.lw.deriveErr = errors.New("the blocks edges of tk-1 did not read")
	o := one(t, d.run(t, pr.Options{}), pr.ActRetry)
	if !strings.Contains(o.Detail, "did not read") || len(d.lw.made()) != 0 {
		t.Fatalf("the run said %q and wrote %q", o.Detail, d.lw.made())
	}
}

// A PR whose bead holds no saved read owes no write until the PR watch saves
// one, and a PR two live beads own owes none, since the store names no one
// bead whose labels it shows.
func TestNoLabelWriteWithoutOneBeadsReadOfThePR(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	md := maps.Clone(d.row(t, bead).Metadata)
	delete(md, "pr_github_read")
	d.store.Put(fake.Bead{ID: bead, Title: "the work", Status: "open", Metadata: md})
	if out := d.run(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a bead with no saved read had %+v", out)
	}
	d = newLabeled(t, []string{"status: working"})
	d.store.Put(fake.Bead{ID: "tk-twin", Title: "more work", Status: "open", Metadata: maps.Clone(d.row(t, bead).Metadata)})
	if out := d.run(t, pr.Options{}); len(out) != 0 || len(d.lw.made()) != 0 {
		t.Fatalf("a PR two beads own had %+v and writes %q", out, d.lw.made())
	}
}

// A PR on the pending record whose merge the PR watch has saved has its labels
// kept in the same run as its record: the run lands the merged PR, and the
// comparison finds its saved labels differ from none and clears them.
func TestTheLandingOrderClearsTheLabelsOfAPRItLands(t *testing.T) {
	d := newLand(t)
	lw := &labelWriter{github: d.github}
	d.l.Labels = lw
	d.pr.Labels = []string{"status: merging"}
	d.pr.Facts.State, d.pr.Facts.MergedAt, d.pr.Facts.MergeCommit = "MERGED", "2026-11-12T08:00:00Z", merged
	d.refresh(t)
	out := d.reconcile(t, pr.Options{})
	actions := map[string]bool{}
	for _, o := range out {
		actions[o.Action] = true
	}
	if !actions[pr.ActLanded] || !actions[pr.ActLabeled] || len(out) != 2 {
		t.Fatalf("the run's outcomes %+v, want the landing and the labels' clear", out)
	}
	if got := lw.made(); !slices.Equal(got, []string{"clear github.com/acme/widgets#7 []"}) {
		t.Fatalf("the writer was asked %q", got)
	}
}

// strays puts on GitHub one labeled PR for each number, which no bead owns.
func (d *labeled) strays(labels []string, numbers ...int) {
	for _, n := range numbers {
		d.github.Put(&ghfake.PR{Facts: gh.PullRequest{Number: n, State: "CLOSED", Repository: repo,
			URL: fmt.Sprintf("https://github.com/acme/widgets/pull/%d", n)}, Labels: slices.Clone(labels)})
	}
}

func urls(numbers ...int) []string {
	var out []string
	for _, n := range numbers {
		out = append(out, fmt.Sprintf("https://github.com/acme/widgets/pull/%d", n))
	}
	return out
}

// The net searches the rig's repository for the writer's labels and clears
// them off each PR no live bead owns, leaving their other labels, and leaves
// an owned PR's labels to the landing order. A page that holds only owned PRs
// never hides the PRs behind it: the search reads on until the results end.
func TestTheNetClearsTheLabelsOfPRsNoLiveBeadOwns(t *testing.T) {
	d := newLabeled(t, []string{"status: merging"})
	eight := &ghfake.PR{Facts: gh.PullRequest{Number: 8, State: "OPEN", Repository: repo, HeadRefName: "polecat/tk-8",
		URL: "https://github.com/acme/widgets/pull/8"}, Labels: []string{"status: working"}}
	d.github.Put(eight)
	d.store.Put(fake.Bead{ID: "tk-8", Title: "more work", Status: "open", Metadata: map[string]string{
		"merge_result": "pull_request", "pr_url": eight.Facts.URL}})
	d.strays([]string{"status: working"}, 3)
	d.strays([]string{"held: gate", "bug"}, 2)
	d.strays([]string{"bug"}, 5)
	d.github.LabeledPage = 2
	rep := d.compare(t)
	if !slices.Equal(rep.Cleared, urls(3, 2)) || len(rep.Failed) != 0 {
		t.Fatalf("the net cleared %q and failed %v, want PRs 3 and 2", rep.Cleared, rep.Failed)
	}
	if got := d.github.Searched(); !slices.Equal(got, []string{"", "cursor:2"}) {
		t.Fatalf("the search read the pages from %q, want the owned page and the one behind it", got)
	}
	if s := rep.Search; s == nil || s.Repository != "github.com/acme/widgets" || s.Pages != 2 || s.Found != 2 || s.Err != nil {
		t.Fatalf("the search reported %+v", rep.Search)
	}
	if got := d.lw.made(); !slices.Equal(got, []string{"clear github.com/acme/widgets#3 []", "clear github.com/acme/widgets#2 []"}) {
		t.Fatalf("the writer was asked %q, want each clear to read the PR's labels itself", got)
	}
	for n, want := range map[int][]string{2: {"bug"}, 3: nil, 5: {"bug"}, 7: {"status: merging"}, 8: {"status: working"}} {
		if got := d.github.PRs[fmt.Sprintf("acme/widgets#%d", n)].Labels; !slices.Equal(got, want) {
			t.Errorf("PR %d shows %q, want %q", n, got, want)
		}
	}
}

// A pass clears at most StrayClears PRs, and reads no page past the one where
// it found them, and the next pass's search finds the rest, as it finds a PR
// whose clear did not land.
func TestTheNetClearsAtMostTwentyAPass(t *testing.T) {
	d := newLabeled(t, []string{"status: merging"})
	var many []int
	for n := 100; n < 100+pr.StrayClears+5; n++ {
		many = append(many, n)
	}
	d.strays([]string{"status: needs-review"}, many...)
	d.github.LabeledPage = 10
	d.lw.fail = 1
	rep := d.compare(t)
	if len(rep.Cleared) != pr.StrayClears-1 || len(rep.Failed) != 1 || rep.Search.Found != pr.StrayClears {
		t.Fatalf("the first pass found %d, cleared %d and failed %v", rep.Search.Found, len(rep.Cleared), rep.Failed)
	}
	if got := d.github.Searched(); rep.Search.Pages != 2 || len(got) != 2 {
		t.Fatalf("the first pass read %d pages, from %q, want the two that hold its twenty", rep.Search.Pages, got)
	}
	failed := slices.Collect(maps.Keys(rep.Failed))[0]
	if !strings.Contains(rep.Failed[failed].Error(), "no live bead owns it") {
		t.Errorf("the failed clear says %v", rep.Failed[failed])
	}
	rep = d.compare(t)
	if len(rep.Cleared) != 6 || !slices.Contains(rep.Cleared, failed) || len(rep.Failed) != 0 {
		t.Fatalf("the second pass cleared %q and failed %v, want the 5 left and %s", rep.Cleared, rep.Failed, failed)
	}
	if rep = d.compare(t); len(rep.Cleared) != 0 || rep.Search.Found != 0 {
		t.Fatalf("a third pass found %d and cleared %q", rep.Search.Found, rep.Cleared)
	}
}

// A search that does not answer, or a rig whose origin does not read, clears
// nothing and says why.
func TestASearchThatFailsClearsNothing(t *testing.T) {
	d := newLabeled(t, []string{"status: merging"})
	d.strays([]string{"status: working"}, 3)
	d.github.Fail["Labeled"] = errors.New("github: HTTP 502")
	if rep := d.compare(t); rep.Search.Err == nil || len(rep.Cleared) != 0 || len(d.lw.made()) != 0 {
		t.Fatalf("a failed search reported %+v and cleared %q", rep.Search, rep.Cleared)
	}
	delete(d.github.Fail, "Labeled")
	d.w.Origin = func() (string, error) { return "", errors.New("no origin") }
	if rep := d.compare(t); rep.Search.Err == nil || len(rep.Cleared) != 0 {
		t.Fatalf("an unread origin reported %+v and cleared %q", rep.Search, rep.Cleared)
	}
}

// The net starts no clear past its window, and the PRs it leaves are found by
// the next pass's search.
func TestTheNetStartsNoClearPastItsWindow(t *testing.T) {
	d := newLabeled(t, []string{"status: merging"})
	d.strays([]string{"status: working"}, 3, 2)
	rep, err := d.w.Compare(pr.PassOptions{Window: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(rep.Late, urls(3, 2)) || len(rep.Cleared) != 0 || len(d.lw.made()) != 0 {
		t.Fatalf("a pass past its window left %q, cleared %q and wrote %q", rep.Late, rep.Cleared, d.lw.made())
	}
	if rep = d.compare(t); !slices.Equal(rep.Cleared, urls(3, 2)) {
		t.Fatalf("the next pass cleared %q", rep.Cleared)
	}
}
