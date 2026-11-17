package pr

import (
	"errors"
	"fmt"
	"maps"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The PR watch (specs/tk-1tfzr71.149/design.md, sections 1, 2, 4, 6 and 7). A
// pass of the cheap question, Poll, asks GitHub whether each PR the city owns
// moved, in one request for each gh.SignsBatch PRs in a repository, and runs
// the one-PR update, Refresh, for each PR whose signs moved. A pass of the net,
// Compare, reads each owned PR in full, in one request for each
// gh.FullReadBatch PRs, and runs the update for each PR whose read differs
// from the read saved on its bead, which catches the changes no sign shows.
// The update reads only the parts of the PR its caller names and saves them on
// the bead that owns the PR. It is the one writer of the saved read, and of Gas
// Town's pr_state and pr_last_checked_at on a bead on the pending record. A
// pass in which nothing moved or differs writes no bead.

// Watch is GitHub as the PR watch reads it: the cheap question and the net's
// full read over many PRs, a PR's own facts with or without the checks at its
// head, its conversation, the login the city's account acts as, and a page of
// the search for the PRs that carry any of a set of labels.
type Watch interface {
	Signs(repo string, numbers []int) (map[int]gh.Signs, map[int]error)
	FullRead(repo string, numbers []int) (map[int]gh.Full, map[int]error)
	PullRequestPart(repo string, number int, checks bool) (*gh.PRPart, error)
	Conversation(repo string, number int) (*gh.Conversation, error)
	Login() (string, error)
	Labeled(repo string, names []string, after string) (gh.LabeledPage, error)
}

// Watcher is what the PR watch reads and writes through. Dir is the store's
// .beads directory, where the record lock lives, and Wait bounds how long an
// update waits for it. Feedback loads the definition of feedback, once a run
// first needs it. Labels is the PRs' labels, which the net clears off a PR no
// live bead owns in the repository Origin's URL names, the rig clone's origin;
// with Labels nil the net clears none.
type Watcher struct {
	Ledger   *ledger.Ledger
	Dir      string
	GitHub   func(host string) Watch
	Feedback func() (Feedback, error)
	Labels   Labels
	Origin   func() (string, error)
	Now      func() time.Time
	Wait     time.Duration
}

// The actions an update reports.
const (
	// ActSaved: the update read the parts the signs made stale and saved those
	// that differ from the saved read.
	ActSaved = "saved"
	// ActUnchanged: nothing moved, or the parts the update read hold what the
	// bead already holds, so it wrote nothing.
	ActUnchanged = "unchanged"
	// ActUnowned: no live bead owns the PR, so there is nothing to save.
	ActUnowned = "unowned"
)

// Refreshed is what an update did with one PR: the PR, the bead that owns it,
// the action and why. A read or a write that failed is the update's error.
type Refreshed struct {
	URL, Bead, Action, Detail string
}

// watchRun is one run of the watch, which reads the login the city's account
// acts as once for each host and loads the definition of feedback once.
type watchRun struct {
	Watcher
	logins map[string]string
	rule   Feedback
}

func (w Watcher) run() *watchRun { return &watchRun{Watcher: w, logins: map[string]string{}} }

func (u *watchRun) login(host string, hub Watch) (string, error) {
	if l, ok := u.logins[host]; ok {
		return l, nil
	}
	l, err := hub.Login()
	if err != nil {
		return "", err
	}
	u.logins[host] = l
	return l, nil
}

func (u *watchRun) feedback() (Feedback, error) {
	if u.rule == nil {
		if u.Feedback == nil {
			return nil, errors.New("nothing loads the definition of feedback")
		}
		rule, err := u.Feedback()
		if err != nil {
			return nil, err
		}
		u.rule = rule
	}
	return u.rule, nil
}

// owners lists the live beads that own a PR, by the PR's URL (ownersIn).
func (w Watcher) owners() (map[string][]owned, error) { return ownersIn(w.Ledger) }

// ownersIn lists the live beads that own a PR, by the PR's URL, read through l.
// A bead owns a PR when it names it as its own and is no other bead's child: an
// anchor names it in pr_url beside a merge_result, and a bead the refinery sent
// back to the pool names it in existing_pr. A bead whose anchor_bead names
// another bead is that bead's child, such as a rework child, and owns nothing.
func ownersIn(l *ledger.Ledger) (map[string][]owned, error) {
	byID := map[string]*ledger.Record{}
	for _, sel := range record.NamingPR() {
		rows, err := l.Find(sel)
		if err != nil {
			return nil, err
		}
		for _, r := range rows {
			byID[r.ID] = r
		}
	}
	out := map[string][]owned{}
	for _, id := range slices.Sorted(maps.Keys(byID)) {
		o, ok := ownerOf(byID[id])
		if ok {
			out[o.url] = append(out[o.url], o)
		}
	}
	return out, nil
}

// ownerOf reads the PR r owns, and false when r owns none: it is closed, it is
// another bead's child, it names no PR as its own, or a key it is read by does
// not decode.
func ownerOf(r *ledger.Record) (owned, bool) {
	if r.Status() == "closed" {
		return owned{}, false
	}
	parent, _, err := anchorKey.Get(r)
	if err != nil {
		return owned{}, false
	}
	if p := strings.TrimSpace(parent); p != "" && p != r.ID {
		return owned{}, false
	}
	rec, err := record.Read(r)
	if err != nil {
		return owned{}, false
	}
	url := rec.ExistingPR
	if rec.Result != "" && rec.URL != "" {
		url = rec.URL
	}
	host, repo, number, ok := record.ParseURL(url)
	if !ok {
		return owned{}, false
	}
	branch, _, berr := record.Branch.Get(r)
	since, _, serr := provenanceKey.Get(r)
	if berr != nil || serr != nil {
		return owned{}, false
	}
	o := owned{id: r.ID, status: r.Status(), assignee: r.Assignee(), url: url, host: host, repo: repo,
		number: number, rec: rec, branch: strings.TrimSpace(branch), since: strings.TrimSpace(since)}
	if saved, _, err := githubReadKey.Get(r); err == nil {
		o.saved = saved
	}
	return o, true
}

// one is the one bead that owns the PR at url among owners, or why there is
// none to save on. More than one is an error, since the store then names no
// one bead for GitHub's side of the PR.
func one(owners []owned, url string) (owned, error) {
	switch len(owners) {
	case 0:
		return owned{}, nil
	case 1:
		return owners[0], nil
	}
	var ids []string
	for _, o := range owners {
		ids = append(ids, o.id)
	}
	return owned{}, fmt.Errorf("%s is owned by more than one live bead (%s), so the update saves it on none",
		url, strings.Join(ids, ", "))
}

// Refresh is the one-PR update called alone, as a webhook's rule can call it: it
// finds the live bead that owns the PR at url, reads the PR's signs itself, and
// reads and saves what they say moved. A PR no live bead owns has nothing to
// save, which it reports with no error.
func (w Watcher) Refresh(url string) (Refreshed, error) {
	host, repo, number, ok := record.ParseURL(url)
	if !ok {
		return Refreshed{}, fmt.Errorf("%q is not a pull request's URL (https://<host>/<owner>/<repo>/pull/<number>)", url)
	}
	all, err := w.owners()
	if err != nil {
		return Refreshed{}, err
	}
	o, err := one(all[url], url)
	if err != nil {
		return Refreshed{URL: url}, err
	}
	if o.id == "" {
		return Refreshed{URL: url, Action: ActUnowned, Detail: "no live bead owns the PR, so there is nothing to save"}, nil
	}
	u := w.run()
	hub := w.GitHub(host)
	at := instant(w.Now)
	signs, failed := hub.Signs(repo, []int{number})
	if err := failed[number]; err != nil {
		return Refreshed{URL: url, Bead: o.id}, fmt.Errorf("the PR's signs did not read: %w", err)
	}
	s, ok := signs[number]
	if !ok {
		return Refreshed{URL: url, Bead: o.id}, errors.New("GitHub returned no signs for the PR")
	}
	return u.update(o, hub, s, at, moved(o.saved, s, o.stale()))
}

// update is the one-PR update over the parts due names, with the signs s, which
// a read sent at signsAt returned: it reads those parts of the PR, then, under
// the record lock, reads the bead again and saves each part that is newer than
// the saved one and differs from it, in one write guarded on the status and the
// assignee that read shows. A bead on the pending record has its pr_state and
// pr_last_checked_at in the same write. A read that fails saves nothing, so the
// PR's saved read stays as it was and the next pass reads it again.
func (u *watchRun) update(o owned, hub Watch, s gh.Signs, signsAt string, due parts) (Refreshed, error) {
	out := Refreshed{URL: o.url, Bead: o.id}
	if !due.any() {
		out.Action, out.Detail = ActUnchanged, "no sign moved"
		return out, nil
	}
	fresh, err := u.read(o, hub, s, signsAt, due)
	if err != nil {
		return out, fmt.Errorf("the PR's %s did not read: %w", due, err)
	}
	return u.save(o, fresh, due)
}

// read reads the parts due names of the PR o owns, and returns them as the
// parts of a saved read, each stamped with the instant its read was sent. The
// labels are their own signs, so they read nothing more.
func (u *watchRun) read(o owned, hub Watch, s gh.Signs, signsAt string, due parts) (*SavedRead, error) {
	fresh := &SavedRead{}
	if due.pr || due.checks {
		at := instant(u.Now)
		p, err := hub.PullRequestPart(o.repo, o.number, due.checks)
		if err != nil {
			return nil, err
		}
		signs := prSigns(s)
		// GitHub computes an open PR's merge state after a push or a base
		// move, and reads it unknown until then: the part keeps its earlier
		// signs, so the next pass finds the PR moved and reads it again. A
		// merged PR's merge state reads unknown for good, so the part of a PR
		// that is not open keeps the signs read with it.
		if p.MergeStateStatus == "UNKNOWN" && p.State == "OPEN" {
			signs = PRSigns{}
			if o.saved != nil && o.saved.PR != nil {
				signs = o.saved.PR.Signs
			}
		}
		fresh.PR = &SavedPR{ReadAt: at, ID: p.ID, URL: p.URL, Number: p.Number, Repository: p.Repository,
			HeadBranch: p.HeadRefName, Base: p.BaseRefName, Head: p.HeadRefOid, State: p.State, Draft: p.IsDraft,
			MergeState: p.MergeStateStatus, InMergeQueue: p.InMergeQueue, MergeQueueEnabled: p.MergeQueueEnabled,
			MergeCommit: p.MergeCommit, MergedAt: p.MergedAt, Signs: signs}
		if due.checks {
			fresh.Checks = &SavedChecks{ReadAt: at, Head: p.ChecksAt, Runs: requiredRuns(p.Suites), Signs: checkSigns(s)}
		}
	}
	if due.conversation {
		rule, err := u.feedback()
		if err != nil {
			return nil, fmt.Errorf("the definition of feedback did not load: %w", err)
		}
		self, err := u.login(o.host, hub)
		if err != nil {
			return nil, err
		}
		at := instant(u.Now)
		c, err := hub.Conversation(o.repo, o.number)
		if err != nil {
			return nil, err
		}
		conv, err := savedConversation(rule, self, o.since, c)
		if err != nil {
			return nil, err
		}
		conv.ReadAt = at
		conv.Signs = ConversationSigns{Comments: s.Comments, Reviews: s.Reviews, Dismissed: s.Dismissed,
			UpdatedAt: s.UpdatedAt, NewestPost: conv.Signs.NewestPost}
		fresh.Conversation = conv
	}
	if due.labels {
		fresh.Labels = &SavedLabels{ReadAt: signsAt, Names: labels(s)}
	}
	return fresh, nil
}

// savedConversation is what the rule reads of a PR's conversation c, by the
// definition of feedback applied from since as the account self acts as, with
// the newest time any post changed as its post time.
func savedConversation(rule Feedback, self, since string, c *gh.Conversation) (*SavedConversation, error) {
	f, err := feedbackOf(rule, self, since, c.Reviews, c.Threads, c.Comments)
	if err != nil {
		return nil, err
	}
	waiting, err := awaiting(rule, self, since, c.Threads)
	if err != nil {
		return nil, err
	}
	approvers, requesters := approval(c.Reviews)
	var unresolved []string
	newest := ""
	for _, v := range c.Reviews {
		newest = later(newest, v.UpdatedAt)
	}
	for _, t := range c.Threads {
		if !t.Resolved {
			unresolved = append(unresolved, t.ID)
		}
		for _, cm := range t.Comments {
			newest = later(newest, cm.UpdatedAt)
		}
	}
	for _, cm := range c.Comments {
		newest = later(newest, cm.UpdatedAt)
	}
	sort.Strings(unresolved)
	return &SavedConversation{Since: since, Approvers: listed(approvers), Requesters: listed(requesters),
		Feedback: f.newest(), Awaiting: listed(waiting), Unresolved: listed(unresolved), ReviewDecision: c.ReviewDecision,
		Approvals: approvals(c.Reviews, c.Threads, f.inline), Signs: ConversationSigns{NewestPost: newest}}, nil
}

// later is the later of two of GitHub's times, a when b does not read as one.
func later(a, b string) string {
	if b != "" && (a == "" || after(b, a)) {
		return b
	}
	return a
}

// save writes the parts of fresh that the bead does not already hold newer or
// the same, under the record lock, as the bead reads under it. A bead that no
// longer owns the PR gets nothing.
func (u *watchRun) save(o owned, fresh *SavedRead, due parts) (Refreshed, error) {
	out := Refreshed{URL: o.url, Bead: o.id}
	release, err := record.Lock(u.Dir, u.Wait)
	if err != nil {
		return out, err
	}
	defer release()
	rows, err := u.Ledger.Find(ledger.ByID(o.id).WithClosed())
	if err != nil {
		return out, err
	}
	if len(rows) == 0 {
		out.Action, out.Detail = ActUnowned, "the store no longer holds the bead"
		return out, nil
	}
	now, ok := ownerOf(rows[0])
	if !ok || now.url != o.url {
		out.Action, out.Detail = ActUnowned, "the bead no longer owns the PR"
		return out, nil
	}
	saved, _, err := githubReadKey.Get(rows[0])
	if err != nil {
		saved = nil
	}
	merged, took := merge(saved, fresh)
	if !took.any() {
		out.Action, out.Detail = ActUnchanged, fmt.Sprintf("read %s, which the bead already holds", due)
		return out, nil
	}
	w := u.Ledger.Write(o.id)
	w.Guard(now.status, now.assignee)
	githubReadKey.Set(w, merged)
	if record.OnRecord(now.rec.Result) && merged.PR != nil {
		record.Refreshed(w, strings.ToLower(merged.PR.State), stamp(u.Now))
	}
	if err := u.Ledger.Commit(w); err != nil {
		if errors.Is(err, ledger.ErrGuard) {
			return out, fmt.Errorf("the bead moved since the update read it, so nothing was saved: %w", err)
		}
		return out, err
	}
	out.Action, out.Detail = ActSaved, fmt.Sprintf("read %s, saved %s", due, took)
	return out, nil
}

// PassOptions bound one pass of the watch: Window is how long after its start
// the pass starts another update.
type PassOptions struct {
	Window time.Duration
}

// PassReport is what a pass did: the PRs it asked about, the repositories they
// are in, each update it ran, each PR that failed with its error, and each PR
// its window left for the next pass. A pass of the net also says what its
// search for the city's labels found, and each PR no live bead owns whose
// labels it cleared.
type PassReport struct {
	Asked, Repositories int
	Updates             []Refreshed
	Failed              map[string]error
	Late                []string
	Search              *Search
	Cleared             []string
}

// sighting is what a pass saw of one PR: the signs it hands the update, and the
// parts of the PR's saved read it found stale.
type sighting struct {
	signs gh.Signs
	due   parts
}

// asker reads, for a pass, every PR owners own in repo through hub, and returns
// a sighting of each PR it read and the error of each PR it did not.
type asker func(hub Watch, repo string, owners []owned) (map[int]sighting, map[int]error)

// Poll is one pass of the cheap question over the PRs the store's live beads
// own: it asks GitHub about every one, in one request for each gh.SignsBatch
// PRs in a repository, and runs the one-PR update for each whose signs moved,
// over the parts they make stale, starting none past o.Window. A PR whose signs
// did not read keeps its saved read, and the pass reports it failed.
func (w Watcher) Poll(o PassOptions) (PassReport, error) {
	report, _, err := w.pass(o, w.clock(), func(hub Watch, repo string, owners []owned) (map[int]sighting, map[int]error) {
		signs, errs := hub.Signs(repo, prNumbers(owners))
		read, failed := map[int]sighting{}, map[int]error{}
		for _, ow := range owners {
			s, ok := signs[ow.number]
			switch {
			case errs[ow.number] != nil:
				failed[ow.number] = fmt.Errorf("its signs did not read: %w", errs[ow.number])
			case !ok:
				failed[ow.number] = errors.New("GitHub returned no signs for it")
			default:
				read[ow.number] = sighting{signs: s, due: moved(ow.saved, s, ow.stale())}
			}
		}
		return read, failed
	})
	return report, err
}

// Compare is one pass of the net over the PRs the store's live beads own: it
// reads every one in full, in one request for each gh.FullReadBatch PRs in a
// repository, and runs the one-PR update for each whose read differs from the
// read saved on its bead, over each part that differs (differs) or whose signs
// moved (moved), starting none past o.Window. So a change no cheap sign shows,
// such as a review thread resolved or an edit to a post that left the PR's
// updatedAt as it was, reaches the saved read within one pass. A PR whose read
// failed keeps its saved read, and the pass reports it failed. With Labels set,
// the pass then searches the rig's repository for the city's labels on PRs no
// live bead owns, and clears them (clearStrays).
func (w Watcher) Compare(o PassOptions) (PassReport, error) {
	start := w.clock()
	report, all, err := w.pass(o, start, func(hub Watch, repo string, owners []owned) (map[int]sighting, map[int]error) {
		full, errs := hub.FullRead(repo, prNumbers(owners))
		read, failed := map[int]sighting{}, map[int]error{}
		for _, ow := range owners {
			f, ok := full[ow.number]
			switch {
			case errs[ow.number] != nil:
				failed[ow.number] = fmt.Errorf("its full read did not answer: %w", errs[ow.number])
			case !ok:
				failed[ow.number] = errors.New("GitHub returned no full read of it")
			default:
				due := moved(ow.saved, f.Signs, ow.stale()).plus(differs(ow.saved, f))
				read[ow.number] = sighting{signs: f.Signs, due: due}
			}
		}
		return read, failed
	})
	if err != nil || w.Labels == nil {
		return report, err
	}
	w.clearStrays(o, start, all, &report)
	return report, nil
}

// clock is the time a pass's window is read by: Now, or the system's clock
// when Now is nil.
func (w Watcher) clock() time.Time {
	if w.Now == nil {
		return time.Now()
	}
	return w.Now()
}

// prNumbers are the numbers of the PRs owners own.
func prNumbers(owners []owned) []int {
	out := make([]int, 0, len(owners))
	for _, o := range owners {
		out = append(out, o.number)
	}
	return out
}

// pass is one pass of the watch over the PRs the store's live beads own, which
// started at start: ask reads every owned PR in a repository, and the pass runs
// the one-PR update over the parts of each PR the read found stale, starting
// none past o.Window. A PR that did not read keeps its saved read, and the pass
// reports it failed, as it does a PR owned by more than one bead and an update
// that did not save. A PR the window left is read at the next pass, since
// nothing saved it. It returns the owners it listed, and an error when the
// store's listing did not read.
func (w Watcher) pass(o PassOptions, start time.Time, ask asker) (PassReport, map[string][]owned, error) {
	now := w.clock
	report := PassReport{Failed: map[string]error{}}
	all, err := w.owners()
	if err != nil {
		return report, nil, err
	}
	type repoKey struct{ host, repo string }
	byRepo := map[repoKey][]owned{}
	for _, url := range slices.Sorted(maps.Keys(all)) {
		owner, err := one(all[url], url)
		if err != nil {
			report.Failed[url] = err
			continue
		}
		k := repoKey{owner.host, strings.ToLower(owner.repo)}
		byRepo[k] = append(byRepo[k], owner)
		report.Asked++
	}
	report.Repositories = len(byRepo)
	u := w.run()
	keys := slices.SortedFunc(maps.Keys(byRepo),
		func(a, b repoKey) int { return strings.Compare(a.host+"/"+a.repo, b.host+"/"+b.repo) })
	for _, k := range keys {
		owners := byRepo[k]
		hub := w.GitHub(k.host)
		at := instant(w.Now)
		read, failed := ask(hub, owners[0].repo, owners)
		for _, ow := range owners {
			if err := failed[ow.number]; err != nil {
				report.Failed[ow.url] = err
				continue
			}
			r, ok := read[ow.number]
			if !ok {
				report.Failed[ow.url] = errors.New("the pass read nothing of it")
				continue
			}
			if !r.due.any() {
				continue
			}
			if o.Window > 0 && now().Sub(start) > o.Window {
				report.Late = append(report.Late, ow.url)
				continue
			}
			done, err := u.update(ow, hub, r.signs, at, r.due)
			if err != nil {
				report.Failed[ow.url] = err
				continue
			}
			report.Updates = append(report.Updates, done)
		}
	}
	return report, all, nil
}
