package refinery

import (
	"cmp"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The refinery's search, `gctk refinery next`, is the work query a refinery
// session claims its one item through (`gc hook --claim`, with the query set as
// the agent's work_query). Gas City starts a refinery session for work assigned
// to it that is ready, or in progress, so every item the search leaves stops
// being that demand, or a session would start, find nothing and stop, and the
// next would start for the same item.
//
// It reads the beads assigned to the refinery, open or in progress, that bd's
// listing shows, and takes one:
//
//   - A bead in progress is a claim a session left, which the hook adopts, so it
//     is taken first, unless something holds it. A held one goes back to open,
//     so the wait, and not the claim, decides when it is taken.
//   - A bead something holds waits until its waits land (waits.Holds). A
//     conversation or an ask on the bead's PR holds its merge and nothing else,
//     so a bead they hold is taken as if they were not there.
//   - A bead with no branch is taken as it is: an effort's hand-off to bring its
//     branch current, or anything else assigned to the refinery, whose session
//     reads it and acts or hands it back.
//   - One writer per branch: a bead is left while another open bead works on
//     its branch, and is made to wait on that bead, so it is no demand until
//     that bead closes. The beads that are no writer are the bead itself, the
//     anchor it names, its PR's asks, the beads that wait here too, and a bead
//     that waits on it and that nobody writes now ([Search.writing]).
//
// Among the beads it can take, the order is: in progress, then a rework child
// handed back before its anchor, then the highest priority, then the oldest.

// anchorKey and taskKindKey are the keys a rework child carries: the bead
// that owns the PR it reworks, and its kind.
var (
	anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
		"The refinery's search takes a rework child before the anchor it names, and the anchor is no writer of "+
			"the child's branch.")
	taskKindKey = ledger.ReadOnly("task_kind", ledger.String,
		"The refinery's search takes a rework child, task_kind rework, before its anchor.")
)

// Item is the row the search prints for the item it takes, as `gc hook
// --claim` reads a work query's row. It carries no blocked_by, since the search
// takes a bead past a conversation or an ask that holds only its PR's merge.
type Item struct {
	ID        string            `json:"id"`
	Title     string            `json:"title"`
	Status    string            `json:"status"`
	Assignee  string            `json:"assignee"`
	IssueType string            `json:"issue_type"`
	Priority  int               `json:"priority"`
	Metadata  map[string]string `json:"metadata,omitempty"`
}

// Left is a bead the search left: why, and what it wrote so the bead is no
// demand for a session while it waits, "" when it wrote nothing.
type Left struct {
	ID    string
	Why   string
	Wrote string
}

// Answer is one search: the item taken, nil when there is none, each bead it
// left, and each write it meant to make and could not, which leaves that bead
// demand for the next session.
type Answer struct {
	Take     *Item
	Left     []Left
	Failures []string
}

// Search is the refinery's search over the store a refinery session works in.
// Refinery is the assignee a hand-off to the refinery writes ($GC_AGENT). Self
// is every name the searching session goes by. Sessions reads the session
// list, which the search asks only for a bead that waits on the one it would
// take and is in progress under another name.
type Search struct {
	Ledger   *ledger.Ledger
	Refinery string
	Self     []string
	Sessions func() ([]gascity.Session, error)
}

// candidate is a bead the search weighs: its record, what holds it, and the
// branch its work is on.
type candidate struct {
	r      *ledger.Record
	holds  waits.Holds
	branch string
	asks   []string
	rank   int
}

// Next reads the store once for the refinery's beads and returns the one item
// to take. A read that fails returns its error and takes nothing.
func (s *Search) Next() (Answer, error) {
	if strings.TrimSpace(s.Refinery) == "" {
		return Answer{}, errors.New("the refinery's identity is empty, and an empty assignee is no filter")
	}
	l := s.Ledger
	rows, err := l.Find(ledger.Assigned(s.Refinery).InStatus("open", "in_progress").Listed())
	if err != nil {
		return Answer{}, fmt.Errorf("the beads assigned to %s did not list: %w", s.Refinery, err)
	}
	rows = slices.DeleteFunc(rows, func(r *ledger.Record) bool {
		st := r.Status()
		return r.Assignee() != s.Refinery || (st != "open" && st != "in_progress")
	})
	if len(rows) == 0 {
		return Answer{}, nil
	}
	ids := make([]string, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	snap, err := waits.Read(l, ids...)
	if err != nil {
		return Answer{}, fmt.Errorf("what holds the beads assigned to %s did not read: %w", s.Refinery, err)
	}
	cands := make([]*candidate, len(rows))
	onBranch := map[string][]*ledger.Record{}
	for i, r := range rows {
		h, err := snap.Holds(r.ID)
		if err != nil {
			return Answer{}, fmt.Errorf("what holds %s did not read: %w", r.ID, err)
		}
		branch, _, err := record.Branch.Get(r)
		if err != nil {
			return Answer{}, err
		}
		c := &candidate{r: r, holds: h, branch: branch}
		if branch != "" {
			if _, read := onBranch[branch]; !read {
				on, err := l.Find(record.OnBranch(branch))
				if err != nil {
					return Answer{}, fmt.Errorf("the open beads on %s did not list: %w", branch, err)
				}
				onBranch[branch] = on
			}
			for _, o := range onBranch[branch] {
				if o.ID != r.ID && review.IsAsk(o, branch) {
					c.asks = append(c.asks, o.ID)
				}
			}
		}
		cands[i] = c
	}
	convs, err := s.conversations(cands)
	if err != nil {
		return Answer{}, err
	}

	var ans Answer
	var clear []*candidate
	for _, c := range cands {
		other := c.otherWaits(convs)
		if c.holds.Status == waits.Clear || (len(c.holds.Waits) > 0 && len(other) == 0) {
			clear = append(clear, c)
			continue
		}
		left := Left{ID: c.r.ID, Why: "something holds it (" + waitsText(c.holds, other) + ")"}
		if c.r.Status() == "in_progress" {
			w := l.Write(c.r.ID)
			w.Status("open")
			w.Guard("in_progress", s.Refinery)
			if err := l.Commit(w); err != nil {
				ans.Failures = append(ans.Failures, fmt.Sprintf("%s, held and in progress, did not go back to open: %v", c.r.ID, err))
			} else {
				left.Wrote = "back to open, so what holds it decides when it is taken"
			}
		}
		ans.Left = append(ans.Left, left)
	}

	waiting := make(map[string]bool, len(rows))
	for _, r := range rows {
		waiting[r.ID] = true
	}
	var takeable []*candidate
	for _, c := range clear {
		writers, err := s.writers(c, onBranch[c.branch], waiting)
		if err != nil {
			return Answer{}, err
		}
		if len(writers) == 0 {
			kind, _, err := taskKindKey.Get(c.r)
			if err != nil {
				return Answer{}, err
			}
			anchor, _, err := anchorKey.Get(c.r)
			if err != nil {
				return Answer{}, err
			}
			switch {
			case c.r.Status() == "in_progress":
				c.rank = 0
			case kind == "rework" && anchor != "":
				c.rank = 1
			default:
				c.rank = 2
			}
			takeable = append(takeable, c)
			continue
		}
		left := Left{ID: c.r.ID, Why: strings.Join(writers, ", ") + " works its branch"}
		var landed []string
		for _, w := range writers {
			if err := l.AddBlocker(c.r.ID, w); err != nil {
				ans.Failures = append(ans.Failures, fmt.Sprintf("%s does not wait on %s, which works its branch: %v", c.r.ID, w, err))
				continue
			}
			landed = append(landed, w)
		}
		if len(landed) > 0 {
			left.Wrote = "waits on " + strings.Join(landed, ", ")
		}
		ans.Left = append(ans.Left, left)
	}
	if len(takeable) == 0 {
		return ans, nil
	}
	slices.SortStableFunc(takeable, func(a, b *candidate) int {
		return cmp.Or(cmp.Compare(a.rank, b.rank), cmp.Compare(a.r.Priority(), b.r.Priority()),
			cmp.Compare(a.r.CreatedAt(), b.r.CreatedAt()), cmp.Compare(a.r.ID, b.r.ID))
	})
	ans.Take = item(takeable[0].r)
	return ans, nil
}

// conversations reads the beads that hold the candidates and returns the ids
// of the conversations among them: a conversation holds its PR's merge and
// nothing else.
func (s *Search) conversations(cands []*candidate) (map[string]bool, error) {
	var waited []string
	for _, c := range cands {
		if c.holds.Status == waits.Clear {
			continue
		}
		for _, w := range c.holds.Waits {
			if w.ID != "" && !slices.Contains(waited, w.ID) {
				waited = append(waited, w.ID)
			}
		}
	}
	convs := map[string]bool{}
	if len(waited) == 0 {
		return convs, nil
	}
	rows, err := s.Ledger.Find(ledger.ByID(waited...).WithClosed())
	if err != nil {
		return nil, fmt.Errorf("the beads that hold the beads did not list: %w", err)
	}
	for _, r := range rows {
		if !conversation.IsCandidate(r.IssueType(), r.Assignee(), r.ID) {
			continue
		}
		edges, err := r.Edges()
		if err != nil {
			return nil, err
		}
		own := make([]conversation.Edge, 0, len(edges))
		for _, e := range edges {
			own = append(own, conversation.Edge{Type: e.Type, DependsOnID: e.ID})
		}
		if _, _, ok := conversation.Shape(own); ok {
			convs[r.ID] = true
		}
	}
	return convs, nil
}

// otherWaits is each wait behind c's status that is neither a conversation nor
// an ask on c's PR.
func (c *candidate) otherWaits(convs map[string]bool) []string {
	var out []string
	for _, w := range c.holds.Waits {
		if !convs[w.ID] && !slices.Contains(c.asks, w.ID) {
			out = append(out, w.ID)
		}
	}
	return out
}

// writers is each other open bead on c's branch that works it: all but c, the
// anchor c names, c's asks and the beads that wait here too, and but a bead
// that waits on c and that nobody writes now.
func (s *Search) writers(c *candidate, on []*ledger.Record, waiting map[string]bool) ([]string, error) {
	if c.branch == "" {
		return nil, nil
	}
	anchor, _, err := anchorKey.Get(c.r)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, o := range on {
		if o.ID == c.r.ID || o.ID == anchor || waiting[o.ID] || slices.Contains(c.asks, o.ID) || slices.Contains(out, o.ID) {
			continue
		}
		branch, _, err := record.Branch.Get(o)
		if err != nil {
			return nil, err
		}
		if branch != c.branch {
			continue
		}
		waitsOn, err := s.waitsOn(o.ID, c.r.ID)
		if err != nil {
			return nil, err
		}
		if waitsOn {
			writing, err := s.writing(o)
			if err != nil {
				return nil, err
			}
			if !writing {
				continue
			}
		}
		out = append(out, o.ID)
	}
	return out, nil
}

// waitsOn reports whether what holds id names bead.
func (s *Search) waitsOn(id, bead string) (bool, error) {
	snap, err := waits.Read(s.Ledger, id)
	if err != nil {
		return false, fmt.Errorf("what holds %s did not read: %w", id, err)
	}
	h, err := snap.Holds(id)
	if err != nil {
		return false, fmt.Errorf("what holds %s did not read: %w", id, err)
	}
	return slices.ContainsFunc(h.Waits, func(w waits.Wait) bool { return w.ID == bead }), nil
}

// writing reports whether someone writes r's branch now: a live run works r,
// or a listed session other than this one holds its in_progress claim, which
// is the test work-setup.sh waits behind a sibling by (work_writing,
// work-lib.sh). A bead open under a live name is handed off, not written, and a
// session list that cannot be read proves nobody gone.
func (s *Search) writing(r *ledger.Record) (bool, error) {
	up, err := s.Ledger.Dependents(r.ID, "tracks")
	if err != nil {
		return false, fmt.Errorf("the runs that work %s did not read: %w", r.ID, err)
	}
	runs, err := waits.LiveRunsOf(s.Ledger, r.ID, up)
	if err != nil {
		return false, fmt.Errorf("the runs that work %s did not read: %w", r.ID, err)
	}
	if len(runs) > 0 {
		return true, nil
	}
	owner := r.Assignee()
	if r.Status() != "in_progress" || owner == "" || slices.Contains(s.Self, owner) {
		return false, nil
	}
	if s.Sessions == nil {
		return true, nil
	}
	sessions, err := s.Sessions()
	if err != nil {
		return true, nil
	}
	return slices.ContainsFunc(sessions, func(se gascity.Session) bool {
		return se.Alias == owner || strings.HasSuffix(se.Alias, owner) || se.SessionName == owner || se.ID == owner
	}), nil
}

// waitsText names what holds a bead: the waits that are no conversation and no
// ask, else its status.
func waitsText(h waits.Holds, other []string) string {
	if len(other) > 0 {
		return strings.Join(other, ", ")
	}
	return string(h.Status)
}

// item is r as the search prints it.
func item(r *ledger.Record) *Item {
	return &Item{ID: r.ID, Title: r.Title(), Status: r.Status(), Assignee: r.Assignee(), IssueType: r.IssueType(),
		Priority: r.Priority(), Metadata: r.Rendered()}
}
