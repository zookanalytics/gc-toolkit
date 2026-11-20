package fake

import (
	"slices"
	"time"
)

// SetLastWrite makes t the newest write the store records under actor.
func (s *Store) SetLastWrite(actor string, t time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.lastWrites == nil {
		s.lastWrites = map[string]time.Time{}
	}
	s.lastWrites[actor] = t
}

// LastWrites answers the newest write SetLastWrite gave each actor named, and
// leaves out an actor it gave none, unless LastWritesErr fails the read.
func (s *Store) LastWrites(actors []string) (map[string]time.Time, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastWriteReads = append(s.lastWriteReads, slices.Clone(actors))
	if s.LastWritesErr != nil {
		return nil, s.LastWritesErr
	}
	out := map[string]time.Time{}
	for _, a := range actors {
		if t, ok := s.lastWrites[a]; ok {
			out[a] = t
		}
	}
	return out, nil
}

// LastWriteReads returns the actors each LastWrites read named, in order.
func (s *Store) LastWriteReads() [][]string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.lastWriteReads)
}
