package pr_test

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"math/rand/v2"
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
// derives over its pass, and writes those it derived only where they differ.
// The net clears the city's labels off the PRs no live bead owns. Each starts
// from the watched world, whose PR the cheap question has read, with its bead
// on the old path so the run owes the record no act and every outcome is a
// label's.

// labelWriter is what the labels' writer is given, as a test sets it: the
// labels the store derives for each bead, a derivation that fails, and the
// labels it names, which the world's repository holds.
type labelWriter struct {
	mu        sync.Mutex
	derived   map[string][]string
	deriveErr error
	derives   [][]string
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

func (*labelWriter) Defined() []gh.Label { return slices.Clone(defined) }

// defined is every label the writer names in these cases.
var defined = []gh.Label{
	{Name: "status: working", Color: "1D76DB", Description: "the city works it"},
	{Name: "status: merging", Color: "1D76DB", Description: "the city lands it"},
	{Name: "status: needs-review", Color: "1D76DB", Description: "a person reviews it"},
	{Name: "status: needs-attention", Color: "1D76DB", Description: "a person clears it"},
	{Name: "held: gate", Color: "D93F0B", Description: "a gate holds it"},
}

// holding has GitHub's repository hold labels.
func holding(g *ghfake.GitHub, labels []gh.Label) {
	if g.Repos == nil {
		g.Repos = map[string]*ghfake.Repo{}
	}
	if g.Repos[repo] == nil {
		g.Repos[repo] = &ghfake.Repo{}
	}
	g.Repos[repo].Labels = slices.Clone(labels)
}

// labelAsks is each label request made of GitHub, in order, as its method, the
// PR or repository it names, and the labels it names.
func labelAsks(g *ghfake.GitHub) []string {
	var out []string
	for _, a := range g.Asks() {
		switch a.Method {
		case "CreateLabel", "EditLabel", "AddLabels", "RemoveLabel":
			out = append(out, a.Method+" "+a.ID+" "+a.Message)
		}
	}
	return out
}

// labelRead reports whether read is one a label write makes of GitHub.
func labelRead(read string) bool { return read == "PullRequestLabels" || read == "RepoLabels" }

// labeled is the watched world with its bead on the old path, the labels'
// writer, and a landing order that keeps the labels, once a pass of the cheap
// question has saved the PR's read. The repository holds every label the
// writer names.
type labeled struct {
	*watched
	lw *labelWriter
	l  pr.Landing
}

func newLabeled(t *testing.T, shows []string) *labeled {
	t.Helper()
	d := newWatched(t)
	d.pr.Labels = shows
	holding(d.github, defined)
	md := maps.Clone(d.md)
	md["merge_result"] = "pull_request"
	d.store.Put(fake.Bead{ID: bead, Title: "the work", Status: "open", Metadata: md})
	lw := &labelWriter{derived: map[string][]string{bead: {"status: merging"}}}
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
// run wrote the store or read GitHub beyond a label write's reads of the
// labels, since a label write writes nothing on the bead, and reads the PR's
// labels and, before an add, the repository's, and nothing else.
func (d *labeled) run(t *testing.T, o pr.Options) []pr.RunOutcome {
	t.Helper()
	reads, writes := len(d.github.Reads()), len(d.store.Writes())
	var out []pr.RunOutcome
	err := d.l.Reconcile(o, func(x pr.RunOutcome) { out = append(out, x) })
	owed := slices.ContainsFunc(out, func(x pr.RunOutcome) bool { return x.Action == pr.ActRetry || x.Action == pr.ActFailed })
	if (err != nil) != owed {
		t.Fatalf("Reconcile returned %v over the outcomes %+v", err, out)
	}
	if got := slices.DeleteFunc(slices.Clone(d.github.Reads()[reads:]), labelRead); len(got) != 0 {
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
// the writer's that the store no longer derives, leaving every other label. It
// reads the PR's labels first, and once the PR watch saves what it wrote, the
// next run finds nothing to write.
func TestTheLandingOrderWritesTheLabelsTheStoreDerives(t *testing.T) {
	for _, tc := range []struct {
		name          string
		shows, derive []string
		asks          []string
		did           string
		after         []string
	}{
		{"a derived label added", nil, []string{"status: needs-review"},
			[]string{"AddLabels acme/widgets#7 status: needs-review"}, "added status: needs-review",
			[]string{"status: needs-review"}},
		{"a stale label taken off", []string{"bug", "held: gate", "status: working"}, []string{"status: working"},
			[]string{"RemoveLabel acme/widgets#7 held: gate"}, "took off held: gate",
			[]string{"bug", "status: working"}},
		{"one swapped for another", []string{"status: working", "bug"}, []string{"status: needs-attention", "held: gate"},
			[]string{"AddLabels acme/widgets#7 status: needs-attention, held: gate", "RemoveLabel acme/widgets#7 status: working"},
			"added status: needs-attention, held: gate and took off status: working",
			[]string{"bug", "held: gate", "status: needs-attention"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := newLabeled(t, tc.shows)
			d.lw.derived[bead] = tc.derive
			o := one(t, d.run(t, pr.Options{}), pr.ActLabeled)
			if want := "where the store derives " + strings.Join(tc.derive, ", ") + ", so the run wrote them: it " + tc.did; !strings.Contains(o.Detail, want) {
				t.Errorf("the outcome says %q, want it to say %q", o.Detail, want)
			}
			if got := labelAsks(d.github); !slices.Equal(got, tc.asks) {
				t.Fatalf("the run asked GitHub %q, want %q", got, tc.asks)
			}
			if got := slices.Sorted(slices.Values(d.pr.Labels)); !slices.Equal(got, tc.after) {
				t.Fatalf("the PR shows %q, want %q", got, tc.after)
			}
			updated(t, d.poll(t), "labels")
			if out := d.run(t, pr.Options{}); len(out) != 0 || len(labelAsks(d.github)) != len(tc.asks) {
				t.Fatalf("the next run reported %+v and asked %q", out, labelAsks(d.github))
			}
		})
	}
}

// A label write reads the PR's labels and the repository's labels on GitHub,
// and nothing of the store: the labels it writes are the ones the run derived
// over its pass, so it lands with every read of the store failing.
func TestALabelWriteReadsNothingOfTheStore(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	finds := -1
	d.l.Hub = func(context.Context, string) pr.Hub {
		finds = len(d.store.Finds())
		d.store.FindErr, d.store.RowsErr = errors.New("no read of the store"), errors.New("no read of the store")
		return d.github
	}
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if got := len(d.store.Finds()); finds < 0 || got != finds {
		t.Fatalf("the store took %d finds before the write and %d after it", finds, got)
	}
	if got := len(d.lw.derives); got != 1 {
		t.Fatalf("the run derived the labels %d times, want once, over its pass", got)
	}
	if !slices.Equal(d.pr.Labels, []string{"status: merging"}) {
		t.Fatalf("the PR shows %q", d.pr.Labels)
	}
}

// The PR's labels are read at the write, so a write the saved read made owes
// changes only what GitHub shows: a label the PR gained since the saved read is
// not added again, and the run says it found the PR already showing the labels.
func TestALabelWriteChangesOnlyWhatThePRShows(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.pr.Labels = []string{"status: merging", "bug"}
	o := one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if !strings.Contains(o.Detail, "found the PR already showing them") {
		t.Errorf("the outcome says %q", o.Detail)
	}
	if got := labelAsks(d.github); len(got) != 0 {
		t.Fatalf("the run asked GitHub %q of a PR that already shows the labels", got)
	}
}

// Before an add, the repository is made to hold every label the writer names:
// one it lacks is made with its colour and description, and one whose
// description differs has it corrected. A write that only takes labels off
// reads nothing of the repository.
func TestAnAddFirstHasTheRepositoryHoldTheLabels(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	stale := slices.Clone(defined[1:4])
	stale[0].Description = "an old description"
	holding(d.github, stale)
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	want := []string{"CreateLabel acme/widgets status: working", "EditLabel acme/widgets status: merging",
		"CreateLabel acme/widgets held: gate", "AddLabels acme/widgets#7 status: merging",
		"RemoveLabel acme/widgets#7 status: working"}
	if got := labelAsks(d.github); !slices.Equal(got, want) {
		t.Fatalf("the run asked GitHub %q, want %q", got, want)
	}
	if got := d.github.Repos[repo].Labels; !slices.Equal(slices.SortedFunc(slices.Values(got), byName),
		slices.SortedFunc(slices.Values(defined), byName)) {
		t.Fatalf("the repository holds %+v, want %+v", got, defined)
	}
	d = newLabeled(t, []string{"held: gate", "status: merging"})
	holding(d.github, nil)
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if got := labelAsks(d.github); !slices.Equal(got, []string{"RemoveLabel acme/widgets#7 held: gate"}) ||
		slices.Contains(d.github.Reads(), "RepoLabels") {
		t.Fatalf("a write that only takes a label off asked GitHub %q and read %q", got, d.github.Reads())
	}
}

func byName(a, b gh.Label) int { return strings.Compare(a.Name, b.Name) }

// A repository whose labels do not read, or a label that is not made, stops no
// add: the add says whether a label it needs is missing, and when it does not
// land, its error says what was not made.
func TestALabelThatIsNotMadeStopsNoAdd(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.github.Fail["RepoLabels"] = errors.New("gh: HTTP 502")
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if !slices.Equal(d.pr.Labels, []string{"status: merging"}) {
		t.Fatalf("the PR shows %q", d.pr.Labels)
	}
	d = newLabeled(t, []string{"status: working"})
	holding(d.github, nil)
	d.github.Fail["CreateLabel"] = errors.New("gh: Must have push access (HTTP 403)")
	d.github.Fail["AddLabels"] = errors.New("gh: Label does not exist (HTTP 422)")
	o := one(t, d.run(t, pr.Options{}), pr.ActRetry)
	for _, want := range []string{"adding status: merging did not land: gh: Label does not exist (HTTP 422)",
		"status: merging was not made: gh: Must have push access (HTTP 403)"} {
		if !strings.Contains(o.Detail, want) {
			t.Errorf("the outcome says %q, want it to say %q", o.Detail, want)
		}
	}
	if !slices.Equal(d.pr.Labels, []string{"status: working"}) {
		t.Fatalf("the PR shows %q after an add that did not land", d.pr.Labels)
	}
}

// Labels that equal the derived ones owe no write, other labels aside, and the
// run reports nothing of them and asks GitHub nothing.
func TestLabelsThatEqualTheDerivedOnesOweNoWrite(t *testing.T) {
	d := newLabeled(t, []string{"held: gate", "bug", "status: needs-attention"})
	d.lw.derived[bead] = []string{"status: needs-attention", "held: gate"}
	reads := len(d.github.Reads())
	if out := d.run(t, pr.Options{}); len(out) != 0 || len(labelAsks(d.github)) != 0 || len(d.github.Reads()) != reads {
		t.Fatalf("the run reported %+v, asked %q and read %q", out, labelAsks(d.github), d.github.Reads()[reads:])
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
			if want := "is " + strings.ToLower(state) + " and showed status: merging, so the run took them off: it took off status: merging"; !strings.Contains(o.Detail, want) {
				t.Errorf("the outcome says %q, want it to say %q", o.Detail, want)
			}
			if got := labelAsks(d.github); !slices.Equal(got, []string{"RemoveLabel acme/widgets#7 status: merging"}) {
				t.Fatalf("the run asked GitHub %q", got)
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

// The run decides a PR's label write on the saved read, with no read of the PR
// but its labels: one the saved read gives closed has the city's labels
// cleared, though GitHub has it open again, and once the watch saves it open,
// the next run writes the labels the store derives.
func TestALabelWriteIsDecidedOnTheSavedRead(t *testing.T) {
	d := newLabeled(t, []string{"status: merging", "bug"})
	d.pr.Facts.State = "CLOSED"
	updated(t, d.poll(t), "pr")
	d.pr.Facts.State = "OPEN"
	o := one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if !strings.Contains(o.Detail, "is closed") {
		t.Errorf("the outcome says %q", o.Detail)
	}
	if got := labelAsks(d.github); !slices.Equal(got, []string{"RemoveLabel acme/widgets#7 status: merging"}) {
		t.Fatalf("the run asked GitHub %q, want the labels cleared on the saved read", got)
	}
	if rep := d.poll(t); len(rep.Failed) != 0 {
		t.Fatalf("the pass failed %v", rep.Failed)
	}
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	if got := labelAsks(d.github); len(got) != 2 || got[1] != "AddLabels acme/widgets#7 status: merging" {
		t.Fatalf("the run asked GitHub %q, want the derived labels written once the watch saved the PR open", got)
	}
}

// A write that does not land records nothing on the bead: the run says so and
// exits as an act that did not complete, and the next run finds the same
// difference and makes the write.
func TestALabelWriteThatFailsIsMadeByTheNextRun(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.github.Fail["AddLabels"] = errors.New("gh: HTTP 502")
	o := one(t, d.run(t, pr.Options{}), pr.ActRetry)
	if !strings.Contains(o.Detail, "nothing records it") || !strings.Contains(o.Detail, "adding status: merging did not land: gh: HTTP 502") {
		t.Errorf("the outcome says %q", o.Detail)
	}
	if before := d.row(t, bead).Metadata; slices.ContainsFunc(slices.Collect(maps.Keys(before)), func(k string) bool {
		return strings.Contains(k, "label")
	}) {
		t.Fatalf("the bead carries a label key after the failed write: %v", before)
	}
	delete(d.github.Fail, "AddLabels")
	one(t, d.run(t, pr.Options{}), pr.ActLabeled)
	want := []string{"AddLabels acme/widgets#7 status: merging", "AddLabels acme/widgets#7 status: merging",
		"RemoveLabel acme/widgets#7 status: working"}
	if got := labelAsks(d.github); !slices.Equal(got, want) {
		t.Fatalf("the runs asked GitHub %q, want %q", got, want)
	}
	if !slices.Equal(d.pr.Labels, []string{"status: merging"}) {
		t.Fatalf("the PR shows %q", d.pr.Labels)
	}
}

// A removal that does not land after the add did says what the write had
// changed, which stands for the next run to read.
func TestALabelRemovalThatFailsSaysWhatLanded(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.github.Fail["RemoveLabel"] = errors.New("gh: HTTP 502")
	o := one(t, d.run(t, pr.Options{}), pr.ActRetry)
	if want := "taking status: working off did not land: gh: HTTP 502, once it had added status: merging"; !strings.Contains(o.Detail, want) {
		t.Errorf("the outcome says %q, want it to say %q", o.Detail, want)
	}
	if got := slices.Sorted(slices.Values(d.pr.Labels)); !slices.Equal(got, []string{"status: merging", "status: working"}) {
		t.Fatalf("the PR shows %q", got)
	}
}

// stalled is GitHub whose read of a PR's labels waits until its act is stopped.
type stalled struct {
	pr.Hub
	ctx context.Context
}

func (s stalled) PullRequestLabels(string, int) ([]string, error) {
	<-s.ctx.Done()
	return nil, fmt.Errorf("gh: the call was stopped: %w", s.ctx.Err())
}

// A label write is an act like the record's: it stops at the run's bound, and
// a run past its window starts none, leaving it to the next run.
func TestALabelWriteKeepsTheRunsBounds(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.l.Hub = func(ctx context.Context, _ string) pr.Hub { return stalled{Hub: d.github, ctx: ctx} }
	o := one(t, d.run(t, pr.Options{Stop: 50 * time.Millisecond}), pr.ActRetry)
	if !strings.Contains(o.Detail, "stopped at its 50ms") {
		t.Errorf("the stopped write says %q", o.Detail)
	}
	d.l.Hub = func(context.Context, string) pr.Hub { return d.github }
	now := time.Date(2026, 11, 16, 11, 0, 0, 0, time.UTC)
	d.l.Now = func() time.Time { now = now.Add(time.Minute); return now }
	o = one(t, d.run(t, pr.Options{Window: 45 * time.Second}), pr.ActLeft)
	if !strings.Contains(o.Detail, "compares the labels of "+prURL) || len(labelAsks(d.github)) != 0 {
		t.Fatalf("the run past its window said %q and asked %q", o.Detail, labelAsks(d.github))
	}
}

// A derivation that does not read writes no label: the run says so and exits
// as an act that did not complete.
func TestALabelDerivationThatFailsWritesNothing(t *testing.T) {
	d := newLabeled(t, []string{"status: working"})
	d.lw.deriveErr = errors.New("the blocks edges of tk-1 did not read")
	o := one(t, d.run(t, pr.Options{}), pr.ActRetry)
	if !strings.Contains(o.Detail, "did not read") || len(labelAsks(d.github)) != 0 {
		t.Fatalf("the run said %q and asked %q", o.Detail, labelAsks(d.github))
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
	if out := d.run(t, pr.Options{}); len(out) != 0 || len(labelAsks(d.github)) != 0 {
		t.Fatalf("a PR two beads own had %+v and asks %q", out, labelAsks(d.github))
	}
}

// A PR on the pending record whose merge the PR watch has saved has its labels
// kept in the same run as its record: the run lands the merged PR, and the
// comparison finds its saved labels differ from none and clears them.
func TestTheLandingOrderClearsTheLabelsOfAPRItLands(t *testing.T) {
	d := newLand(t)
	d.l.Labels = &labelWriter{}
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
	if got := labelAsks(d.github); !slices.Equal(got, []string{"RemoveLabel acme/widgets#7 status: merging"}) {
		t.Fatalf("the run asked GitHub %q", got)
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
	if got := labelAsks(d.github); !slices.Equal(got, []string{"RemoveLabel acme/widgets#3 status: working",
		"RemoveLabel acme/widgets#2 held: gate"}) {
		t.Fatalf("the net asked GitHub %q, want the city's labels each PR shows taken off", got)
	}
	if got := slices.DeleteFunc(slices.Clone(d.github.Reads()), func(r string) bool { return r != "PullRequestLabels" }); len(got) != 2 {
		t.Fatalf("the net read %d PRs' labels, want each PR it cleared read once", len(got))
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
	once := &flaky{Watch: d.github, fails: 1}
	d.w.GitHub = func(string) pr.Watch { return once }
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
	if rep := d.compare(t); rep.Search.Err == nil || len(rep.Cleared) != 0 || len(labelAsks(d.github)) != 0 {
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
	if !slices.Equal(rep.Late, urls(3, 2)) || len(rep.Cleared) != 0 || len(labelAsks(d.github)) != 0 {
		t.Fatalf("a pass past its window left %q, cleared %q and asked %q", rep.Late, rep.Cleared, labelAsks(d.github))
	}
	if rep = d.compare(t); !slices.Equal(rep.Cleared, urls(3, 2)) {
		t.Fatalf("the next pass cleared %q", rep.Cleared)
	}
}

// flaky is GitHub whose removal of a label fails while fails counts down.
type flaky struct {
	pr.Watch
	fails int
}

func (f *flaky) RemoveLabel(repo string, number int, name string) error {
	if f.fails > 0 {
		f.fails--
		return errors.New("gh: HTTP 502")
	}
	return f.Watch.RemoveLabel(repo, number, name)
}

// slowClear is GitHub with a read of one PR's labels that fails once elapse
// has moved the clock past the pass's window.
type slowClear struct {
	pr.Watch
	number int
	elapse func()
}

func (s slowClear) PullRequestLabels(repo string, number int) ([]string, error) {
	if number == s.number {
		s.elapse()
		return nil, errors.New("gh: HTTP 502")
	}
	return s.Watch.PullRequestLabels(repo, number)
}

// A PR whose clear keeps failing after taking the net's whole window holds no
// other PR back: over a few passes, the shuffled order reaches the PR the
// search finds after it.
func TestAStrayWhoseClearKeepsFailingSlowlyHoldsNoOtherBack(t *testing.T) {
	d := newLabeled(t, []string{"status: merging"})
	d.strays([]string{"status: working"}, 3, 2)
	slow := slowClear{Watch: d.github, number: 3, elapse: func() { d.clock = d.clock.Add(3*time.Minute + time.Second) }}
	d.w.GitHub = func(string) pr.Watch { return slow }
	src := rand.New(rand.NewPCG(1, 2))
	d.w.Shuffle = func(ids []string) { src.Shuffle(len(ids), func(i, j int) { ids[i], ids[j] = ids[j], ids[i] }) }
	passes := 0
	for ; passes < 10 && len(d.github.PRs["acme/widgets#2"].Labels) != 0; passes++ {
		if rep := d.compare(t); rep.Failed[urls(3)[0]] == nil {
			t.Fatalf("pass %d cleared %q and failed %v, want PR 3 failed", passes, rep.Cleared, rep.Failed)
		}
	}
	if got := d.github.PRs["acme/widgets#2"].Labels; len(got) != 0 {
		t.Fatalf("PR 2 still shows %q after %d passes behind PR 3's slow failing clear", got, passes)
	}
}
