package pr

import (
	"context"
	"fmt"
)

// A review run's round fixes the PR's title and summary on the bead that owns
// the PR, and its push brings the PR's own title and body current with the
// bead's composition (Edit), so the next round's lanes, which read the PR as
// published, judge what the bead records. The refinery composes the same text
// from the same bead when it publishes a head it validated.

// Edited is what Edit found and did: the PR it read, the composition of the
// PR's title and body, and whether it edited the PR's title and its body, each
// only where the composition differs from what the PR shows.
type Edited struct {
	URL         string
	Composition *Composition
	Title, Body bool
}

// EditRefusal is an edit the PR's state refused: the bead names no PR, or the
// PR is not open, or not open from the bead's branch. The PR is left as it
// stands.
type EditRefusal struct{ Bead, Why string }

func (e *EditRefusal) Error() string {
	return fmt.Sprintf("%s: the PR is left as it stands: %s", e.Bead, e.Why)
}

// Edit brings the title and the body of the PR the bead owns current with the
// bead's composition at req's head. It reads the PR's title and body, composes
// with that body as the one published, and edits, in one request, the title
// when it differs in more than spacing and the body when a section of it was
// written, and asks nothing when neither moved. A composition with no title
// leaves the PR's title as it stands. The PR is the one url names, else the
// one the bead's record names, else the one the bead records for the refinery
// to reuse, and it must be in the rig's own repository, open, and open from
// the bead's branch when the bead records one. An edit GitHub refused or did
// not answer is an error, and the PR may show either text, so the caller runs
// Edit again, which edits what still differs.
func (l Landing) Edit(bead, url string, req Request) (Edited, error) {
	o, why, err := l.owned(bead, url)
	if err != nil {
		return Edited{URL: o.url}, err
	}
	if why != "" {
		return Edited{}, &EditRefusal{Bead: bead, Why: why}
	}
	hub := l.Hub(context.Background(), o.host)
	p, err := hub.PullRequestText(o.repo, o.number)
	if err != nil {
		return Edited{URL: o.url}, err
	}
	if why := notOpenFrom(&p.PullRequest, o.branch); why != "" {
		return Edited{URL: o.url}, &EditRefusal{Bead: bead, Why: why}
	}
	req.Body = &p.Body
	c, err := Compose(l.Ledger, bead, req)
	if err != nil {
		return Edited{URL: o.url}, err
	}
	var title, body *string
	if c.Title != "" && words(c.Title) != words(p.Title) {
		title = &c.Title
	}
	if c.Summary == Written || c.BranchBeads == Written {
		body = &c.Body
	}
	if title == nil && body == nil {
		return Edited{URL: o.url, Composition: c}, nil
	}
	if err := hub.EditPullRequest(p.ID, title, body); err != nil {
		return Edited{URL: o.url, Composition: c}, fmt.Errorf("PR %s's title and body did not take, so it may still show the earlier ones: %w", o.url, err)
	}
	return Edited{URL: o.url, Composition: c, Title: title != nil, Body: body != nil}, nil
}
