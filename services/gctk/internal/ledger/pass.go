package ledger

import (
	"errors"
	"slices"
	"strings"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Pass returns a ledger that reads the store once: every read of a bead
// through it answers with the row it kept the first time it read that bead,
// whatever selects the bead. Once it has read every live bead (Every), it
// answers a selection of live beads from the rows it holds without reading the
// store, so every question asked through it in one pass answers from one read.
// It reads the store's blocked set once. It takes no write, because a write
// would leave its rows stale.
//
// What the rows it holds cannot answer it reads first: a bead named that it
// has not read, a selection that reaches closed beads, any selection before it
// holds every live bead, and the beads the store lists under a parent, which
// only the store answers. Reads run without holding the pass, so two at once
// can read one bead, and the row kept first answers both.
func (l *Ledger) Pass() *Ledger {
	return &Ledger{store: &pass{store: l.store, rows: map[string]*gcbd.Bead{}, absent: map[string]bool{}}}
}

// pass is the store a Pass reads through.
type pass struct {
	store gcbd.Store

	mu sync.Mutex
	// rows is every row the pass kept, by id, and order their ids in the order
	// it kept them.
	rows  map[string]*gcbd.Bead
	order []string
	// absent is the ids a read of closed and live beads found the store does
	// not hold.
	absent map[string]bool
	// listed is true once the pass holds every live bead's row.
	listed  bool
	blocked *gcbd.BlockedSet
}

var _ gcbd.Store = (*pass)(nil)

// errPassWrite refuses a write through a pass.
var errPassWrite = errors.New("ledger: a pass reads the store and takes no write")

func (p *pass) Rows(ids []string) ([]gcbd.Bead, error) {
	return nil, &gcbd.ReadError{Reason: "a pass answers from the rows it read, and reads no row afresh"}
}

func (p *pass) Update(id string, args ...string) (string, error) { return "", errPassWrite }

// Ready reads the store's ready set afresh each time it is asked: readiness is
// the store's answer at the moment it is read, and no row the pass keeps
// answers it.
func (p *pass) Ready(q gcbd.ReadyQuery) ([]gcbd.Bead, error) { return p.store.Ready(q) }

// Blocked reads the store's blocked set the first time it is asked, and answers
// with that read every time after.
func (p *pass) Blocked() (*gcbd.BlockedSet, error) {
	p.mu.Lock()
	b := p.blocked
	p.mu.Unlock()
	if b != nil {
		return b, nil
	}
	b, err := p.store.Blocked()
	if err != nil {
		return nil, err
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.blocked == nil {
		p.blocked = b
	}
	return p.blocked, nil
}

// Find answers q from the rows the pass holds, once it has read what those
// rows cannot answer.
func (p *pass) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	if q.Parent != "" {
		rows, err := p.store.Find(q)
		if err != nil {
			return nil, err
		}
		p.mu.Lock()
		defer p.mu.Unlock()
		var out []gcbd.Bead
		for _, r := range p.keep(rows) {
			if q.Closed || live(r) {
				out = append(out, *r)
			}
		}
		return out, nil
	}
	p.mu.Lock()
	ask, need := p.ask(q)
	p.mu.Unlock()
	if need {
		rows, err := p.store.Find(ask)
		if err != nil {
			return nil, err
		}
		p.mu.Lock()
		p.keep(rows)
		if ask.Closed {
			for _, id := range ask.IDs {
				if p.rows[id] == nil {
					p.absent[id] = true
				}
			}
		}
		if q.Every && !q.Closed && len(q.IDs) == 0 && q.HasKey == "" && q.Key == "" {
			p.listed = true
		}
		p.mu.Unlock()
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	var out []gcbd.Bead
	for _, id := range p.order {
		if r := p.rows[id]; selected(q, r) {
			out = append(out, *r)
		}
	}
	return out, nil
}

// ask is the read q needs before the rows the pass holds answer it, and
// whether it needs one: none once the pass holds every live bead and q selects
// live beads alone, and of the beads q names, only the ones it has not read.
func (p *pass) ask(q gcbd.Query) (gcbd.Query, bool) {
	if p.listed && !q.Closed {
		return q, false
	}
	if len(q.IDs) == 0 {
		return q, true
	}
	ask := q
	ask.IDs = nil
	for _, id := range q.IDs {
		if p.rows[id] == nil && !p.absent[id] && !slices.Contains(ask.IDs, id) {
			ask.IDs = append(ask.IDs, id)
		}
	}
	return ask, len(ask.IDs) > 0
}

// keep adds each row the pass has not kept before, and returns, for each row
// given, the row the pass holds for that bead.
func (p *pass) keep(rows []gcbd.Bead) []*gcbd.Bead {
	out := make([]*gcbd.Bead, 0, len(rows))
	for i := range rows {
		id := rows[i].ID
		if p.rows[id] == nil {
			r := rows[i]
			p.rows[id] = &r
			p.order = append(p.order, id)
			delete(p.absent, id)
		}
		out = append(out, p.rows[id])
	}
	return out
}

// live reports whether a row is live: any status but closed.
func live(r *gcbd.Bead) bool { return r.StatusLower() != "closed" }

// selected reports whether q selects r: its status, the ids named, the key it
// carries, the value that key holds and the text its title holds, as the
// store's listing selects them. A key's value compares as the scripts render
// it, `(.metadata[k] // "") | tostring`.
func selected(q gcbd.Query, r *gcbd.Bead) bool {
	if !q.Closed && !live(r) {
		return false
	}
	if len(q.IDs) > 0 && !slices.Contains(q.IDs, r.ID) {
		return false
	}
	if q.TitleContains != "" && !strings.Contains(r.Title, q.TitleContains) {
		return false
	}
	if q.HasKey != "" {
		if _, held := r.Metadata[q.HasKey]; !held {
			return false
		}
	}
	if q.Key != "" {
		if _, held := r.Metadata[q.Key]; !held || r.Meta(q.Key) != q.Value {
			return false
		}
	}
	return true
}
