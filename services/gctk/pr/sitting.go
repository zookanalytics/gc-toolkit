package pr

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// A converse sitting's push onto the branch of a PR on the pending record
// (specs/tk-1tfzr71.108/design.md, section 10). The sitting edits the branch on
// the operator's ruling while its conversation holds the bead that owns the PR
// through a blocks edge, the edge a conversation on an open PR writes. While
// that edge holds the bead, the landing order pours no review run on it
// (heldBy) and the refinery's find-work does not take it, so the sitting is the
// branch's one writer. The proof reads under the store's record lock, which the
// landing order holds from its read of a record to its pour, so a run that read
// the bead before the edge was added has poured before the proof reads, and the
// proof sees it attached. The push holds the lock from its proof to its end, so
// in that time the order pours no run, and its ready transition, which reads no
// conversation's hold, does not mark the PR ready between its return to draft
// and the push. Every other writer of the record waits for that lock, so the
// push holds it for at most half the time a writer waits for it (Wait). A call
// to GitHub, origin or the store still running then is stopped with every
// process it started, and the lock goes free only once they have ended, since a
// push that landed after that could land on a PR the order had marked ready in
// the meantime. The checkout's own reads, its origin's URLs and its status, read
// files and reach no remote, so nothing bounds them. The push goes only to the
// PR's repository: every URL the checkout's origin fetches from or pushes to
// must name it. It returns the PR to draft first, as every writer of the city
// does, and goes under git's lease on the tip it reads on the branch, so a push
// another writer made is never overwritten. Once the conversation closes, the
// refinery validates the head the sitting left and the landing order pours one
// review run there, as for any other head.

// Tree is the sitting's checkout of the PR's branch.
type Tree interface {
	// Origin lists the URLs the checkout's origin fetches from and the ones a
	// push to it goes to, as git resolves them.
	Origin() (fetch, push []string, err error)
	// Uncommitted lists what the checkout holds that the commit at its HEAD
	// does not, and is empty when it holds nothing more.
	Uncommitted() (string, error)
	// Push pushes the commit at the checkout's HEAD onto branch on origin,
	// under git's lease on the tip it reads there, and never forces it. It
	// returns a *Moved when that tip is a commit HEAD does not descend from,
	// or when the branch moved between the read and the push, and then
	// nothing landed. A push still running once ctx is done is stopped with
	// every process it started before Push returns, with an error that wraps
	// ctx's cause.
	Push(ctx context.Context, branch string) error
}

// Moved is a push that took nothing because the branch holds a commit the
// sitting's HEAD does not descend from, such as one another writer pushed.
type Moved struct{ Branch, Why string }

func (e *Moved) Error() string {
	return fmt.Sprintf("nothing was pushed onto %s, which holds a commit this checkout's HEAD does not: %s", e.Branch, e.Why)
}

// PushRefusal is a push the sitting may not make now: what the proof found, a
// checkout whose origin reaches a repository other than the PR's, or work in
// the checkout that no commit holds. Nothing was changed.
type PushRefusal struct{ Bead, Why string }

func (e *PushRefusal) Error() string {
	return fmt.Sprintf("%s: nothing was changed: %s", e.Bead, e.Why)
}

// LockTimeUp is the cause of a call that was stopped because the push had held
// the store's record lock for After, the most it may, so that a writer waiting
// for the lock gets it. What the push had done by then stands, so the PR may be
// a draft and the push may have landed.
type LockTimeUp struct{ After time.Duration }

func (e *LockTimeUp) Error() string {
	return fmt.Sprintf("the push held the store's record lock for %s, the most it may", e.After)
}

// underLock takes the record lock, waiting up to l.Wait while another writer
// holds it and no longer once ctx is done, and returns the context the calls
// made under the lock run in and the call that ends that context and releases
// the lock. The context ends once the lock has been held for half of l.Wait,
// with a *LockTimeUp as its cause, so a writer that waits as long gets the
// lock, with time to spare for the stop of a call still running.
func (l Landing) underLock(ctx context.Context) (context.Context, func(), error) {
	release, err := record.LockContext(ctx, l.Dir, l.Wait)
	if err != nil {
		return nil, nil, err
	}
	most := l.Wait / 2
	ctx, cancel := context.WithTimeoutCause(ctx, most, &LockTimeUp{After: most})
	return ctx, func() { cancel(); release() }, nil
}

// Holding is what the proof found: the branch of the PR the bead owns, which
// the conversation holds, and PR, the URL of the PR its record names.
type Holding struct{ Bead, Conversation, Branch, PR string }

// Pushed is what Push did: the holding it proved and the PR it returned to
// draft, or found a draft already.
type Pushed struct {
	Holding
	Drafted
}

// Held proves that the sitting that holds conversation conv may write the branch of
// the PR bead owns, where conv is the conversation's id and self names this
// session as a claim records it. The bead
// must own a PR on the pending record and name its branch. The conversation
// must be in progress under this session, and the bead must wait on it
// through a blocks edge. No review run may be attached to the bead, and no
// open bead other than an ask may name its branch. It reads under the record
// lock, as Push does, and its reads end once it has held the lock for half of
// l.Wait or once ctx is done. A *PushRefusal names every reason the proof
// failed, and a read that did not answer, or a lock another writer held as
// long as l.Wait, is an error.
func (l Landing) Held(ctx context.Context, bead, conv string, self []string) (Holding, error) {
	ctx, release, err := l.underLock(ctx)
	if err != nil {
		return Holding{}, err
	}
	defer release()
	return l.within(ctx).held(bead, conv, self)
}

// held is Held's proof, read by a caller that holds the record lock.
func (l Landing) held(bead, conv string, self []string) (Holding, error) {
	r, err := l.read(bead)
	if err != nil {
		return Holding{}, err
	}
	if r == nil {
		return Holding{}, &PushRefusal{Bead: bead, Why: "the store holds no such bead"}
	}
	rec, err := record.Read(r)
	if err != nil {
		return Holding{}, err
	}
	branch, _, err := record.Branch.Get(r)
	if err != nil {
		return Holding{}, err
	}
	branch = strings.TrimSpace(branch)
	var why []string
	if r.Status() == "closed" {
		why = append(why, "it is closed")
	}
	if !record.OnRecord(rec.Result) {
		why = append(why, fmt.Sprintf("it owns no PR open on the pending record (merge_result %q)", rec.Result))
	}
	if branch == "" {
		why = append(why, "it names no branch")
	}
	switch _, _, _, ok := record.ParseURL(rec.URL); {
	case rec.URL == "":
		why = append(why, "its record names no PR")
	case !ok:
		why = append(why, fmt.Sprintf("its record's %q is not a pull request's URL", rec.URL))
	}
	c, err := l.read(conv)
	if err != nil {
		return Holding{}, err
	}
	switch {
	case c == nil:
		why = append(why, "the store holds no conversation "+conv)
	case !conversation.IsCandidate(strings.ToLower(c.IssueType()), c.Assignee(), c.ID):
		why = append(why, conv+" is no conversation held by a sitting")
	case c.Status() != "in_progress" || !slices.Contains(self, c.Assignee()):
		why = append(why, fmt.Sprintf("conversation %s is %s and assigned to %s, so this session does not hold it", conv, c.Status(), nobody(c.Assignee())))
	}
	blockers, err := l.blockers(r, true)
	if err != nil {
		return Holding{}, err
	}
	if !slices.ContainsFunc(blockers, func(b *ledger.Record) bool { return b.ID == conv }) {
		why = append(why, "it has no blocks edge onto conversation "+conv+", which keeps the landing order's review runs and the refinery off its branch")
	}
	runs, err := runsIn(blockers)
	if err != nil {
		return Holding{}, err
	}
	if len(runs) > 0 {
		why = append(why, "review run "+strings.Join(runs, ", ")+" is attached to it and works its branch")
	}
	if branch != "" {
		others, err := l.writers(bead, branch)
		if err != nil {
			return Holding{}, err
		}
		if len(others) > 0 {
			why = append(why, strings.Join(others, ", ")+" works its branch "+branch)
		}
	}
	if len(why) > 0 {
		return Holding{}, &PushRefusal{Bead: bead, Why: strings.Join(why, "; ")}
	}
	return Holding{Bead: bead, Conversation: conv, Branch: branch, PR: rec.URL}, nil
}

// Push pushes the commit at the tree's HEAD onto the branch of the PR bead
// owns, for the sitting that holds conversation conv. It takes the record lock
// and holds it to its end, proves the holding first as Held does, refuses a
// tree whose origin reaches a repository other than the PR's or that holds work
// no commit holds, and returns the PR to draft before it pushes, so a draft
// that did not land pushes nothing. A branch that holds a commit the tree's
// HEAD does not returns a *Moved, with the PR left a draft for the push that
// follows once the tree holds that commit too. Once it has held the lock for
// half of l.Wait, or once ctx is done, the store, GitHub or tree call still
// running is stopped with every process it started, and Push returns that
// call's error, which wraps a *LockTimeUp or ctx's cause, and releases the lock
// only once the call has returned.
func (l Landing) Push(ctx context.Context, bead, conv string, self []string, t Tree) (Pushed, error) {
	ctx, release, err := l.underLock(ctx)
	if err != nil {
		return Pushed{}, err
	}
	defer release()
	in := l.within(ctx)
	h, err := in.held(bead, conv, self)
	if err != nil {
		return Pushed{}, err
	}
	fetch, push, err := t.Origin()
	if err != nil {
		return Pushed{Holding: h}, fmt.Errorf("the checkout's origin did not read: %w", err)
	}
	if why := elsewhere(h.PR, fetch, push); why != "" {
		return Pushed{Holding: h}, &PushRefusal{Bead: bead, Why: why}
	}
	left, err := t.Uncommitted()
	if err != nil {
		return Pushed{Holding: h}, err
	}
	if strings.TrimSpace(left) != "" {
		return Pushed{Holding: h}, &PushRefusal{Bead: bead, Why: "the checkout holds work no commit holds, which a push would leave behind: " + joinLines(left)}
	}
	d, err := in.Draft(bead, h.PR)
	if err != nil {
		return Pushed{Holding: h, Drafted: d}, err
	}
	if err := t.Push(ctx, h.Branch); err != nil {
		var moved *Moved
		if errors.As(err, &moved) {
			return Pushed{Holding: h, Drafted: d}, err
		}
		return Pushed{Holding: h, Drafted: d}, fmt.Errorf("the push onto %s did not land: %w", h.Branch, err)
	}
	return Pushed{Holding: h, Drafted: d}, nil
}

// elsewhere says which URLs of the checkout's origin name a repository other
// than that of the PR at url, of fetch, the ones it fetches from, and push, the
// ones a push to it goes to, and is empty when every one names the PR's. Each
// URL is held to the comparison Draft holds the rig's clone to
// (outsideOrigin), and an origin that lists no URL binds nothing to the PR, so
// it is refused too. A URL is named by the repository it names, so no
// credentials it carries are repeated, and by itself when it names none.
func elsewhere(url string, fetch, push []string) string {
	host, repo, _, _ := record.ParseURL(url)
	var names []string
	verbs := map[string]string{}
	var why []string
	for _, side := range []struct {
		verb string
		urls []string
	}{{"fetches from", fetch}, {"pushes to", push}} {
		if len(side.urls) == 0 {
			why = append(why, "it "+side.verb+" no URL")
		}
		for _, u := range side.urls {
			if outsideOrigin(u, host, repo) == "" {
				continue
			}
			name := u + ", which names no repository on a host"
			if oh, orepo, ok := originRepo(u); ok {
				name = oh + "/" + orepo
			}
			switch v, seen := verbs[name]; {
			case !seen:
				names = append(names, name)
				verbs[name] = side.verb
			case v != side.verb:
				verbs[name] = "fetches from and pushes to"
			}
		}
	}
	for _, n := range names {
		why = append(why, "it "+verbs[n]+" "+n)
	}
	if len(why) == 0 {
		return ""
	}
	return fmt.Sprintf("the checkout's origin is not the PR's repository, %s/%s: %s", host, repo, strings.Join(why, "; "))
}

// joinLines joins the lines of a listing into one, for a message.
func joinLines(s string) string {
	return strings.Join(strings.Fields(strings.ReplaceAll(strings.TrimSpace(s), "\n", "; ")), " ")
}
