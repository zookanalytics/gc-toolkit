package pr

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// A converse sitting's push onto the branch of a PR on the pending record
// (specs/tk-1tfzr71.108/design.md, section 10). The sitting edits the branch on
// the operator's ruling while its conversation holds the bead that owns the PR
// through a blocks edge, the edge a conversation on an open PR writes. While
// that edge holds the bead, the landing order pours no review run on it
// (heldBy) and the refinery's find-work does not take it, so the sitting is
// the branch's one writer. The push returns the PR to draft first, as every
// writer of the city does, and goes under git's lease on the tip it reads on
// the branch, so a push another writer made is never overwritten. Once the
// conversation closes, the refinery validates the head the sitting left and
// the landing order pours one review run there, as for any other head.

// Tree is the sitting's checkout of the PR's branch.
type Tree interface {
	// Uncommitted lists what the checkout holds that the commit at its HEAD
	// does not, and is empty when it holds nothing more.
	Uncommitted() (string, error)
	// Push pushes the commit at the checkout's HEAD onto branch on origin,
	// under git's lease on the tip it reads there, and never forces it. It
	// returns a *Moved when that tip is a commit HEAD does not descend from,
	// or when the branch moved between the read and the push, and then
	// nothing landed.
	Push(branch string) error
}

// Moved is a push that took nothing because the branch holds a commit the
// sitting's HEAD does not descend from, such as one another writer pushed.
type Moved struct{ Branch, Why string }

func (e *Moved) Error() string {
	return fmt.Sprintf("nothing was pushed onto %s, which holds a commit this checkout's HEAD does not: %s", e.Branch, e.Why)
}

// PushRefusal is a push the sitting may not make now: what the proof found,
// or work in the checkout that no commit holds. Nothing was changed.
type PushRefusal struct{ Bead, Why string }

func (e *PushRefusal) Error() string {
	return fmt.Sprintf("%s: nothing was changed: %s", e.Bead, e.Why)
}

// Holding is what the proof found: the branch of the PR the bead owns, which
// the conversation holds.
type Holding struct{ Bead, Conversation, Branch string }

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
// open bead other than an ask may name its branch. A *PushRefusal names every
// reason the proof failed, and a read that did not answer is an error.
func (l Landing) Held(bead, conv string, self []string) (Holding, error) {
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
	return Holding{Bead: bead, Conversation: conv, Branch: branch}, nil
}

// Push pushes the commit at the tree's HEAD onto the branch of the PR bead
// owns, for the sitting that holds conversation conv. It proves the holding first
// (Held), refuses a tree that holds work no commit holds, and returns the PR
// to draft before it pushes, so a draft that did not land pushes nothing. A
// branch that holds a commit the tree's HEAD does not returns a *Moved, with
// the PR left a draft for the push that follows once the tree holds that
// commit too.
func (l Landing) Push(bead, conv string, self []string, t Tree) (Pushed, error) {
	h, err := l.Held(bead, conv, self)
	if err != nil {
		return Pushed{}, err
	}
	left, err := t.Uncommitted()
	if err != nil {
		return Pushed{Holding: h}, err
	}
	if strings.TrimSpace(left) != "" {
		return Pushed{Holding: h}, &PushRefusal{Bead: bead, Why: "the checkout holds work no commit holds, which a push would leave behind: " + joinLines(left)}
	}
	d, err := l.Draft(bead, "")
	if err != nil {
		return Pushed{Holding: h, Drafted: d}, err
	}
	if err := t.Push(h.Branch); err != nil {
		var moved *Moved
		if errors.As(err, &moved) {
			return Pushed{Holding: h, Drafted: d}, err
		}
		return Pushed{Holding: h, Drafted: d}, fmt.Errorf("the push onto %s did not land: %w", h.Branch, err)
	}
	return Pushed{Holding: h, Drafted: d}, nil
}

// joinLines joins the lines of a listing into one, for a message.
func joinLines(s string) string {
	return strings.Join(strings.Fields(strings.ReplaceAll(strings.TrimSpace(s), "\n", "; ")), " ")
}
