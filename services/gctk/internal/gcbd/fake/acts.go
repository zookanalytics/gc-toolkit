package fake

import (
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Close is one gate resolve or one reopen the store took: the bead and its
// reason.
type Close struct {
	ID, Reason string
}

// Unrelate removes the relates-to edge between id and other from both rows, as
// bd's dep unrelate does, and records it. A bead the store does not hold
// refuses it.
func (s *Store) Unrelate(id, other string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.UnrelateErr != nil {
		return "", s.UnrelateErr
	}
	for _, x := range []string{id, other} {
		if _, ok := s.rows[x]; !ok {
			return "", fmt.Errorf("fake store: no bead %s", x)
		}
	}
	for _, pair := range [][2]string{{id, other}, {other, id}} {
		b := s.rows[pair[0]]
		b.Edges = slices.DeleteFunc(slices.Clone(b.Edges), func(e gcbd.Edge) bool {
			return e.ID == pair[1] && e.Type == gcbd.EdgeRelatesTo
		})
		s.rows[pair[0]] = b
	}
	s.unrelates = append(s.unrelates, Edge{ID: id, Far: other, Type: gcbd.EdgeRelatesTo})
	s.wrote("unrelate", id, []string{other})
	return "", nil
}

// Unrelates returns every unrelate the store took, in order.
func (s *Store) Unrelates() []Edge {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.unrelates)
}

// ResolveGate closes the gate id with reason, as bd's gate resolve does, and
// records it: a bead that is no gate refuses it, and a gate already closed
// stays as it is and the resolve still succeeds, as bd's does. Each edge onto
// the gate takes its new status and close time, as a show row of the bead
// waiting on it reports them.
func (s *Store) ResolveGate(id, reason string) (string, error) {
	if s.BeforeResolve != nil {
		if err := s.BeforeResolve(id, reason); err != nil {
			return "", err
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ResolveErr != nil {
		return "", s.ResolveErr
	}
	b, ok := s.rows[id]
	if !ok {
		return "", fmt.Errorf("fake store: gate not found: %s", id)
	}
	if b.IssueType != "gate" {
		return "", fmt.Errorf("fake store: %s is not a gate issue (type=%s)", id, b.IssueType)
	}
	s.resolves = append(s.resolves, Close{ID: id, Reason: reason})
	if !strings.EqualFold(b.Status, "closed") {
		b.Status, b.CloseReason = "closed", reason
		if b.ClosedAt == "" {
			b.ClosedAt = s.CloseTime
		}
		s.rows[id] = b
		s.restate(id, "closed", b.ClosedAt)
	}
	s.wrote("gate-resolve", id, []string{"--reason", reason})
	return "", nil
}

// Resolves returns every gate resolve the store took, in order.
func (s *Store) Resolves() []Close {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.resolves)
}

// Reopen opens id again, as bd's reopen does: its close time and close reason
// go, each edge onto it reads open again, and the reopen is recorded. A bead
// the store does not hold refuses it, and one already open stays as it is.
func (s *Store) Reopen(id, reason string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ReopenErr != nil {
		return "", s.ReopenErr
	}
	b, ok := s.rows[id]
	if !ok {
		return "", fmt.Errorf("fake store: no bead %s", id)
	}
	s.reopens = append(s.reopens, Close{ID: id, Reason: reason})
	if strings.EqualFold(b.Status, "closed") {
		b.Status, b.CloseReason, b.ClosedAt = "open", "", ""
		s.rows[id] = b
		s.restate(id, "open", "")
	}
	s.wrote("reopen", id, []string{"--reason", reason})
	return "", nil
}

// Reopens returns every reopen the store took, in order.
func (s *Store) Reopens() []Close {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.reopens)
}

// restate gives each edge onto id the far bead's new status and close time.
// Its caller holds the lock.
func (s *Store) restate(id, status, closedAt string) {
	for other, b := range s.rows {
		changed := false
		edges := slices.Clone(b.Edges)
		for i, e := range edges {
			if e.ID == id {
				edges[i].Status, edges[i].ClosedAt = status, closedAt
				changed = true
			}
		}
		if changed {
			b.Edges = edges
			s.rows[other] = b
		}
	}
}

// parented is b's edges with its parent-child edges replaced by one onto
// parent, as bd's update --parent sets a bead's one parent, or with none when
// parent is empty. A parent the store does not hold refuses the update, and so
// does one that sits under b, which bd refuses as a cycle.
func (s *Store) parented(b Bead, parent string) ([]gcbd.Edge, error) {
	edges := slices.DeleteFunc(slices.Clone(b.Edges), func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeParentChild })
	if parent == "" {
		return edges, nil
	}
	p, ok := s.rows[parent]
	if !ok {
		return nil, fmt.Errorf("fake store: no parent %s", parent)
	}
	for seen, up := map[string]bool{}, parent; up != "" && !seen[up]; {
		if up == b.ID {
			return nil, fmt.Errorf("fake store: %s sits under %s, so it cannot be its parent", parent, b.ID)
		}
		seen[up] = true
		next := ""
		for _, e := range s.rows[up].Edges {
			if e.Type == gcbd.EdgeParentChild {
				next = e.ID
				break
			}
		}
		up = next
	}
	return append(edges, gcbd.Edge{Type: gcbd.EdgeParentChild, ID: parent, Title: p.Title, Status: p.Status}), nil
}
