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

// The PR watch (specs/tk-1tfzr71.149/design.md, sections 1, 4, 6 and 7). A
// pass of the cheap question, Poll, asks GitHub whether each PR the city owns
// moved, in one request for each gh.SignsBatch PRs in a repository, and runs
// the one-PR update, Refresh, for each PR whose signs moved. The update reads
// only the parts of the PR the moved signs make stale and saves them on the
// bead that owns the PR. It is the one writer of the saved read, and of Gas
// Town's pr_state and pr_last_checked_at on a bead on the pending record. A
// pass in which nothing moved writes no bead.

// Watch is GitHub as the PR watch reads it: the cheap question over many PRs,
// a PR's own facts with or without the checks at its head, its conversation,
// and the login the city's account acts as.
type Watch interface {
	Signs(repo string, numbers []int) (map[int]gh.Signs, map[int]error)
	PullRequestPart(repo string, number int, checks bool) (*gh.PRPart, error)
	Conversation(repo string, number int) (*gh.Conversation, error)
	Login() (string, error)
}

// Watcher is what the PR watch reads and writes through. Dir is the store's
// .beads directory, where the record lock lives, and Wait bounds how long an
// update waits for it. Feedback loads the definition of feedback, once a run
// first needs it.
type Watcher struct {
	Ledger   *ledger.Ledger
	Dir      string
	GitHub   func(host string) Watch
	Feedback func() (Feedback, error)
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

// owners lists the live beads that own a PR, by the PR's URL. A bead owns a PR
// when it names it as its own and is no other bead's child: an anchor names it
// in pr_url beside a merge_result, and a bead the refinery sent back to the
// pool names it in existing_pr. A bead whose anchor_bead names another bead is
// that bead's child, such as a rework child, and owns nothing.
func (w Watcher) owners() (map[string][]owned, error) {
	byID := map[string]*ledger.Record{}
	for _, sel := range record.NamingPR() {
		rows, err := w.Ledger.Find(sel)
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

// Refresh is the one-PR update called alone, as a webhook's rule calls it: it
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
	return u.update(o, hub, s, at)
}

// update is the one-PR update over the signs s, which a read sent at signsAt
// returned: it reads the parts of the PR the signs say moved, then, under the
// record lock, reads the bead again and saves each part that is newer than the
// saved one and differs from it, in one write guarded on the status and the
// assignee that read shows. A bead on the pending record has its pr_state and
// pr_last_checked_at in the same write. A read that fails saves nothing, so the
// PR's signs stay as they were and the next pass reads it again.
func (u *watchRun) update(o owned, hub Watch, s gh.Signs, signsAt string) (Refreshed, error) {
	out := Refreshed{URL: o.url, Bead: o.id}
	due := moved(o.saved, s, o.stale())
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
		// GitHub computes a merge state after a push or a base move, and reads
		// it unknown until then: the part keeps its earlier signs, so the next
		// pass finds the PR moved and reads it again.
		if p.MergeStateStatus == "UNKNOWN" {
			signs = PRSigns{}
			if o.saved != nil && o.saved.PR != nil {
				signs = o.saved.PR.Signs
			}
		}
		fresh.PR = &SavedPR{ReadAt: at, URL: p.URL, Number: p.Number, Repository: p.Repository,
			HeadBranch: p.HeadRefName, Base: p.BaseRefName, Head: p.HeadRefOid, State: p.State, Draft: p.IsDraft,
			MergeState: p.MergeStateStatus, InMergeQueue: p.InMergeQueue, MergeQueueEnabled: p.MergeQueueEnabled,
			Signs: signs}
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
		conv, err := conversation(rule, self, o.since, c)
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

// conversation is what the rule reads of a PR's conversation c, by the
// definition of feedback applied from since as the account self acts as, with
// the newest time any post changed as its post time.
func conversation(rule Feedback, self, since string, c *gh.Conversation) (*SavedConversation, error) {
	fresh, err := newestFeedback(rule, self, since, c.Reviews, c.Threads, c.Comments)
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
		Feedback: fresh, Awaiting: listed(waiting), Unresolved: listed(unresolved), ReviewDecision: c.ReviewDecision,
		Signs: ConversationSigns{NewestPost: newest}}, nil
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

// PollOptions bound one pass: Window is how long after its start it starts
// another update.
type PollOptions struct {
	Window time.Duration
}

// PollReport is what a pass did: the PRs it asked about, the repositories they
// are in, each PR whose signs moved, and each PR that failed with its error.
type PollReport struct {
	Asked, Repositories int
	Updates             []Refreshed
	Failed              map[string]error
	Late                []string
}

// Poll is one pass of the cheap question over the PRs the store's live beads
// own: it asks GitHub about every one, in one request for each gh.SignsBatch
// PRs in a repository, and runs the one-PR update for each whose signs moved,
// starting none past o.Window. A PR whose signs did not read keeps its saved
// signs, and the pass reports it failed, as it does a PR owned by more than
// one bead and an update that did not save. A PR the window left is read at
// the next pass, since nothing saved its signs. It returns an error when the
// store's listing did not read.
func (w Watcher) Poll(o PollOptions) (PollReport, error) {
	now := w.Now
	if now == nil {
		now = time.Now
	}
	start := now()
	report := PollReport{Failed: map[string]error{}}
	all, err := w.owners()
	if err != nil {
		return report, err
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
		var numbers []int
		for _, ow := range owners {
			numbers = append(numbers, ow.number)
		}
		at := instant(w.Now)
		signs, failed := hub.Signs(owners[0].repo, numbers)
		for _, ow := range owners {
			if err := failed[ow.number]; err != nil {
				report.Failed[ow.url] = fmt.Errorf("its signs did not read: %w", err)
				continue
			}
			s, ok := signs[ow.number]
			if !ok {
				report.Failed[ow.url] = errors.New("GitHub returned no signs for it")
				continue
			}
			if !moved(ow.saved, s, ow.stale()).any() {
				continue
			}
			if o.Window > 0 && now().Sub(start) > o.Window {
				report.Late = append(report.Late, ow.url)
				continue
			}
			done, err := u.update(ow, hub, s, at)
			if err != nil {
				report.Failed[ow.url] = err
				continue
			}
			report.Updates = append(report.Updates, done)
		}
	}
	return report, nil
}
