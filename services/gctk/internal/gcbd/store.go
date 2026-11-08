package gcbd

// Store is the bead store as the ledger reaches it, and the seam the fake stands
// in at. *Client is the store the city runs, and gcbd/fake's Store is the one a
// domain's tests run on.
type Store interface {
	// Rows reads each bead named, with its own edges, from the store itself, so
	// the read sees a write just made. A read that fails returns a *ReadError,
	// and so does a bead named that it reads no row for, because the store's
	// reply cannot tell a bead it does not hold from one whose lookup failed.
	Rows(ids []string) ([]Bead, error)
	// Blocked reads the store's blocked set once, for Answer to judge beads
	// against. A read that fails returns a *ReadError.
	Blocked() (*BlockedSet, error)
	// Update makes one `gc bd update` of id with args, returning its output.
	// An error is a write that did not land.
	Update(id string, args ...string) (string, error)
}

var _ Store = (*Client)(nil)
