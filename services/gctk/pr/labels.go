package pr

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The PRs' status: and held: labels, kept by comparison
// (specs/tk-1tfzr71.149/design.md, section 9). The landing order compares the
// labels the one-PR update saved on each owned PR's bead with the ones the
// store derives, and has the labels' one writer write only where they differ:
// the derived labels on an open PR, and none on one that merged or closed. The
// net searches the rig's repository for the city's labels on PRs no live bead
// owns, and has the writer clear them. Nothing records a write that does not
// land: the difference stays, and a later run writes it again.

// Labels is the PRs' labels as the store derives them and their one writer
// keeps them (assets/scripts/pr-status-label.sh). The derivation is prstatus's,
// which imports this package, so the caller hands it over.
type Labels interface {
	// Derive returns the labels the store derives for the open PR each bead
	// named owns, read through pass, and the error of each bead it could not
	// derive them for.
	Derive(pass *ledger.Ledger, beads []string) (map[string][]string, map[string]error)
	// Kept reports whether the writer keeps the label named, which it takes off
	// a PR when it derives none of that name.
	Kept(name string) bool
	// Names returns every label the writer names.
	Names() []string
	// Reconcile has the writer derive the labels of the open PR bead owns,
	// number in repo, owner/name, on host, and write them where they differ
	// from current, the labels the PR shows, or from the labels it reads itself
	// when current is empty. It stops once ctx ends.
	Reconcile(ctx context.Context, bead, host, repo string, number int, current []string) error
	// Clear has the writer take every label it keeps off the PR, from current as
	// Reconcile reads it. It stops once ctx ends.
	Clear(ctx context.Context, host, repo string, number int, current []string) error
}

// StrayClears is the most PRs no live bead owns whose labels a pass of the net
// clears in the rig's repository.
const StrayClears = 20

// labelWrite is the write one owned PR's labels owe: the bead that owns it,
// the PR, every label the one-PR update saved on the bead, the ones among them
// the writer keeps, the ones the store derives, and the state that ended the
// PR, MERGED or CLOSED, empty while it is open.
type labelWrite struct {
	bead, url, host, repo string
	number                int
	current, have, want   []string
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
			current: s.Labels.Names, have: kept(s.Labels.Names, u.Labels.Kept)}
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

// writeLabels makes the write w owes through the labels' writer, stopped at
// stop: the labels the store derives on an open PR, none on one that merged
// or closed. A write that does not land records nothing, so the next run finds
// the same difference and writes it again.
func (u *run) writeLabels(w labelWrite, stop time.Duration) RunOutcome {
	ctx, cancel := context.Background(), context.CancelFunc(func() {})
	if stop > 0 {
		ctx, cancel = context.WithTimeout(ctx, stop)
	}
	defer cancel()
	var err error
	var done string
	if w.ended != "" {
		err = u.Labels.Clear(ctx, w.host, w.repo, w.number, w.current)
		done = fmt.Sprintf("%s is %s and showed %s, so the labels' writer took them off",
			w.url, strings.ToLower(w.ended), shown(w.have))
	} else {
		err = u.Labels.Reconcile(ctx, w.bead, w.host, w.repo, w.number, w.current)
		done = fmt.Sprintf("%s showed %s where the store derives %s, so the labels' writer wrote them",
			w.url, shown(w.have), shown(w.want))
	}
	if err != nil {
		why := err.Error()
		if ctx.Err() != nil {
			why = fmt.Sprintf("the act was stopped at its %s: %s", stop, why)
		}
		return RunOutcome{Bead: w.bead, Action: ActRetry, Detail: fmt.Sprintf("the labels of %s did not land, and "+
			"nothing records it, so the next run compares them again: %s", w.url, why)}
	}
	return RunOutcome{Bead: w.bead, Action: ActLabeled, Detail: done}
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
// found StrayClears PRs that no live bead owns or the results end, and has the
// writer clear each, starting none past o.Window, which start began. A page
// that holds only owned PRs never hides the ones behind it. all is the owners
// the pass listed. A clear that does not land is reported failed, and the next
// pass's search finds the PR again. Only the rig's own repository is searched,
// since a PR in another is owned by the beads of that repository's rig.
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
	host, repo, ok := originRepo(raw)
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
	names := w.Labels.Names()
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
	for _, n := range strays {
		url := fmt.Sprintf("https://%s/%s/pull/%d", host, repo, n)
		if o.Window > 0 && w.clock().Sub(start) > o.Window {
			report.Late = append(report.Late, url)
			continue
		}
		if err := w.Labels.Clear(context.Background(), host, repo, n, nil); err != nil {
			report.Failed[url] = fmt.Errorf("no live bead owns it, and its labels did not come off: %w", err)
			continue
		}
		report.Cleared = append(report.Cleared, url)
	}
}
