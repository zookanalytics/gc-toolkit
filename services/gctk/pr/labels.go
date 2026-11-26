package pr

import (
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The PRs' status: and held: labels, kept by comparison
// (specs/tk-1tfzr71.149/design.md, section 9). A label is a view of the saved
// read and the store. The landing order compares the labels the one-PR update
// saved on each owned PR's bead with the ones the store derives over its pass,
// and where they differ, it writes the labels it derived, reading the PR's
// labels first: the derived labels on a PR the saved read shows open, and none
// on one it shows merged or closed. The net searches the rig's repository for
// the city's labels on PRs no live bead owns, and takes them off. Nothing
// records a write that does not land, or one a saved read out of date made
// wrong: the difference stays, and a later run writes it again.

// Labels is the city's labels as their writer is handed them: the ones the
// store derives for each PR, which labels it keeps, and every label it names,
// with its colour and description. The derivation and the names are
// prstatus's, which imports this package, so the caller hands them over.
type Labels interface {
	// Derive returns the labels the store derives for the open PR each bead
	// named owns, read through pass, and the error of each bead it could not
	// derive them for.
	Derive(pass *ledger.Ledger, beads []string) (map[string][]string, map[string]error)
	// Kept reports whether the writer keeps the label named, which it takes off
	// a PR when it derives none of that name.
	Kept(name string) bool
	// Defined returns every label the writer names, as a repository holds it
	// once the writer has made it.
	Defined() []gh.Label
}

// Labeling is GitHub as the labels' writer reaches it: the labels a PR
// carries, the labels its repository holds, a label's creation and the edit of
// its description, and the labels added to a PR or taken off it.
type Labeling interface {
	PullRequestLabels(repo string, number int) ([]string, error)
	RepoLabels(repo string) ([]gh.Label, error)
	CreateLabel(repo string, l gh.Label) error
	EditLabel(repo string, l gh.Label) error
	AddLabels(repo string, number int, names []string) error
	RemoveLabel(repo string, number int, name string) error
}

// putLabels brings the labels labels keeps on PR number in repo to want,
// through hub, and returns what it changed, empty when it changed nothing: it
// reads the labels the PR carries, adds each of want the PR lacks, in want's
// order, then takes off each label it keeps that want does not name, leaving
// every other label. Before an add it has the repository hold every label
// labels names, with its colour and description (ensureLabels). A read or a
// write that does not land returns an error naming it, and what the write had
// changed by then stands for the next write to read.
func putLabels(hub Labeling, labels Labels, repo string, number int, want []string) (string, error) {
	carried, err := hub.PullRequestLabels(repo, number)
	if err != nil {
		return "", fmt.Errorf("the PR's labels did not read: %w", err)
	}
	var shows, add, remove []string
	for _, n := range carried {
		if labels.Kept(n) && !slices.Contains(shows, n) {
			shows = append(shows, n)
		}
	}
	for _, n := range want {
		if !slices.Contains(shows, n) && !slices.Contains(add, n) {
			add = append(add, n)
		}
	}
	for _, n := range shows {
		if !slices.Contains(want, n) {
			remove = append(remove, n)
		}
	}
	var did []string
	if len(add) > 0 {
		made := ensureLabels(hub, labels, repo)
		if err := hub.AddLabels(repo, number, add); err != nil {
			if made != nil {
				err = fmt.Errorf("%w, after the labels it names were not all made: %w", err, made)
			}
			return "", fmt.Errorf("adding %s did not land: %w", shown(add), err)
		}
		did = append(did, "added "+shown(add))
	}
	for i, n := range remove {
		if err := hub.RemoveLabel(repo, number, n); err != nil {
			had := slices.Clone(did)
			if i > 0 {
				had = append(had, "taken off "+shown(remove[:i]))
			}
			if len(had) > 0 {
				err = fmt.Errorf("%w, once it had %s", err, strings.Join(had, " and "))
			}
			return "", fmt.Errorf("taking %s off did not land: %w", n, err)
		}
	}
	if len(remove) > 0 {
		did = append(did, "took off "+shown(remove))
	}
	return strings.Join(did, " and "), nil
}

// ensureLabels has repo hold every label labels names, as it names it: it
// creates each label repo lacks, and corrects the description of each whose
// description differs. It returns what did not land, which stops nothing: the
// add it comes before goes ahead, and carries it in its error when the add
// does not land either.
func ensureLabels(hub Labeling, labels Labels, repo string) error {
	have, err := hub.RepoLabels(repo)
	if err != nil {
		return fmt.Errorf("the repository's labels did not read, so none was made: %w", err)
	}
	var failed []string
	for _, d := range labels.Defined() {
		i := slices.IndexFunc(have, func(l gh.Label) bool { return l.Name == d.Name })
		switch {
		case i < 0:
			if err := hub.CreateLabel(repo, d); err != nil {
				failed = append(failed, fmt.Sprintf("%s was not made: %v", d.Name, err))
			}
		case have[i].Description != d.Description:
			if err := hub.EditLabel(repo, d); err != nil {
				failed = append(failed, fmt.Sprintf("the description of %s was not corrected: %v", d.Name, err))
			}
		}
	}
	if len(failed) > 0 {
		return errors.New(strings.Join(failed, "; "))
	}
	return nil
}

// StrayClears is the most PRs no live bead owns whose labels a pass of the net
// clears in the rig's repository.
const StrayClears = 20

// labelWrite is the write one owned PR's labels owe, as the comparison found
// it: the bead that owns it, the PR, the labels the writer keeps among the
// ones the one-PR update saved on the bead, the ones the store derives, and the
// state the saved read gives that ended the PR, MERGED or CLOSED, empty while
// it is open.
type labelWrite struct {
	bead, url, host, repo string
	number                int
	have, want            []string
	ended                 string
}

// labelPlans are the label writes the PRs the store's live beads own owe, read
// through pass, which has listed every live bead: one for each PR whose saved
// labels the writer keeps differ from the ones the store derives. A PR whose
// bead holds no saved read of it, or whose read is of another PR, owes none
// until the PR watch saves one, and a PR more than one live bead owns owes
// none, since the store names no one bead whose labels it shows. A PR whose
// derivation did not read owes a retry, which writes nothing.
func (u *run) labelPlans(pass *ledger.Ledger) ([]plan, error) {
	all, err := ownersIn(pass)
	if err != nil {
		return nil, err
	}
	var writes []labelWrite
	var open []string
	for _, url := range slices.Sorted(maps.Keys(all)) {
		if len(all[url]) != 1 {
			continue
		}
		o := all[url][0]
		s := o.saved
		if s == nil || s.PR == nil || s.Labels == nil || !strings.EqualFold(s.PR.Repository, o.repo) ||
			s.PR.Number != o.number {
			continue
		}
		w := labelWrite{bead: o.id, url: url, host: o.host, repo: o.repo, number: o.number,
			have: kept(s.Labels.Names, u.Labels.Kept)}
		switch s.PR.State {
		case "MERGED", "CLOSED":
			w.ended = s.PR.State
		case "OPEN":
			open = append(open, o.id)
		default:
			continue
		}
		writes = append(writes, w)
	}
	var derived map[string][]string
	failed := map[string]error{}
	if len(open) > 0 {
		derived, failed = u.Labels.Derive(pass, open)
	}
	var out []plan
	for _, w := range writes {
		if w.ended == "" {
			want, ok := derived[w.bead]
			if !ok {
				why := failed[w.bead]
				if why == nil {
					why = errors.New("the derivation gave none")
				}
				out = append(out, plan{id: w.url, out: RunOutcome{Bead: w.bead, Action: ActRetry,
					Detail: fmt.Sprintf("the labels the store derives for %s did not read, so none is written and "+
						"the next run compares them again: %v", w.url, why)}})
				continue
			}
			w.want = want
		}
		if sameLabels(w.have, w.want) {
			continue
		}
		write := w
		out = append(out, plan{id: w.url, write: &write})
	}
	return out, nil
}

// kept is each label named that the writer keeps, in their order.
func kept(names []string, keeps func(string) bool) []string {
	var out []string
	for _, n := range names {
		if keeps(n) {
			out = append(out, n)
		}
	}
	return out
}

// sameLabels reports whether a and b name the same labels, in any order.
func sameLabels(a, b []string) bool {
	return slices.Equal(slices.Compact(slices.Sorted(slices.Values(a))), slices.Compact(slices.Sorted(slices.Values(b))))
}

// shown is a set of labels as an outcome names it.
func shown(labels []string) string {
	if len(labels) == 0 {
		return "none"
	}
	return strings.Join(labels, ", ")
}

// writeLabels makes the write w owes through GitHub, stopped at stop: the
// labels the store derived over the run's pass on a PR the saved read shows
// open, and none on one it shows merged or closed. It reads the PR's labels
// first and changes only those that differ (putLabels), and reads nothing of
// the store. A write that does not land records nothing, so the next run finds
// the same difference and writes it again.
func (u *run) writeLabels(w labelWrite, stop time.Duration) RunOutcome {
	ctx, cancel := bounded(stop)
	defer cancel()
	did, err := putLabels(u.Hub(ctx, w.host), u.Labels, w.repo, w.number, w.want)
	if err != nil {
		why := err.Error()
		if ctx.Err() != nil {
			why = fmt.Sprintf("the act was stopped at its %s: %s", stop, why)
		}
		return RunOutcome{Bead: w.bead, Action: ActRetry, Detail: fmt.Sprintf("the labels of %s did not land, and "+
			"nothing records it, so the next run compares them again: %s", w.url, why)}
	}
	if did == "" {
		did = "found the PR already showing them"
	}
	if w.ended != "" {
		return RunOutcome{Bead: w.bead, Action: ActLabeled, Detail: fmt.Sprintf(
			"%s is %s and showed %s, so the run took them off: it %s", w.url, strings.ToLower(w.ended), shown(w.have), did)}
	}
	return RunOutcome{Bead: w.bead, Action: ActLabeled, Detail: fmt.Sprintf(
		"%s showed %s where the store derives %s, so the run wrote them: it %s", w.url, shown(w.have), shown(w.want), did)}
}

// Search is what a pass of the net's search for the city's labels did in the
// rig's repository: the repository, the pages it read, the PRs it found that no
// live bead owns, at most StrayClears, and the error that ended it.
type Search struct {
	Repository   string
	Pages, Found int
	Err          error
}

// clearStrays searches the rig's repository, the one its clone's origin names,
// for PRs that carry a label the writer names, a page at a time, until it has
// found StrayClears PRs that no live bead owns or the results end, and takes
// the labels it keeps off each (putLabels), in a shuffled order, so one whose
// clear is slow or keeps failing holds no other back, starting none past
// o.Window, which start began.
// A page that holds only owned PRs never hides the ones behind it. all is the
// owners the pass listed. A clear that does not land is reported failed, and
// the next pass's search finds the PR again. Only the rig's own repository is
// searched, since a PR in another is owned by the beads of that repository's
// rig.
func (w Watcher) clearStrays(o PassOptions, start time.Time, all map[string][]owned, report *PassReport) {
	search := &Search{}
	report.Search = search
	if w.Origin == nil {
		search.Err = errors.New("nothing reads the rig's origin")
		return
	}
	raw, err := w.Origin()
	if err != nil {
		search.Err = fmt.Errorf("the rig's origin did not read: %w", err)
		return
	}
	host, repo, ok := git.RemoteRepository(raw)
	if !ok {
		search.Err = fmt.Errorf("the rig's origin %q names no GitHub repository", raw)
		return
	}
	search.Repository = host + "/" + repo
	owned := map[int]bool{}
	for url := range all {
		h, r, n, ok := record.ParseURL(url)
		if ok && strings.EqualFold(h, host) && strings.EqualFold(r, repo) {
			owned[n] = true
		}
	}
	hub := w.GitHub(host)
	var names []string
	for _, l := range w.Labels.Defined() {
		names = append(names, l.Name)
	}
	var strays []int
	for after := ""; len(strays) < StrayClears; {
		page, err := hub.Labeled(repo, names, after)
		if err != nil {
			search.Err = err
			break
		}
		search.Pages++
		for _, p := range page.PRs {
			if !owned[p.Number] && !slices.Contains(strays, p.Number) && len(strays) < StrayClears {
				strays = append(strays, p.Number)
			}
		}
		if page.Next == "" {
			break
		}
		after = page.Next
	}
	search.Found = len(strays)
	urls := make([]string, 0, len(strays))
	numbers := map[string]int{}
	for _, n := range strays {
		url := fmt.Sprintf("https://%s/%s/pull/%d", host, repo, n)
		urls = append(urls, url)
		numbers[url] = n
	}
	w.shuffle(urls)
	for _, url := range urls {
		if o.Window > 0 && w.clock().Sub(start) > o.Window {
			report.Late = append(report.Late, url)
			continue
		}
		if _, err := putLabels(hub, w.Labels, repo, numbers[url], nil); err != nil {
			report.Failed[url] = fmt.Errorf("no live bead owns it, and its labels did not come off: %w", err)
			continue
		}
		report.Cleared = append(report.Cleared, url)
	}
}
