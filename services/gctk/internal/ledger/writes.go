package ledger

import "time"

// LastWrites reads the newest write the store records under each actor named,
// such as a session's identity, from the write log bd keeps beside its rows,
// and leaves out an actor it records none by. A read that fails returns its
// *ReadError.
func (l *Ledger) LastWrites(actors ...string) (map[string]time.Time, error) {
	return l.store.LastWrites(actors)
}

// LastWrites reads the store's write log afresh each time it is asked, since a
// pass keeps rows and the log is no row.
func (p *pass) LastWrites(actors []string) (map[string]time.Time, error) {
	return p.store.LastWrites(actors)
}
