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
	// Find reads the beads q selects, in the listing's shape: each row's own
	// edges name the far bead and the edge's type, whether or not the store
	// holds the far bead, and carry none of its fields. A bead q names that the
	// store does not hold is left out, since one list query answers for every
	// bead it names. A read that fails returns a *ReadError.
	Find(q Query) ([]Bead, error)
	// Ready reads the beads q selects that the store reports ready, in the
	// listing's shape. A read that fails returns a *ReadError.
	Ready(q ReadyQuery) ([]Bead, error)
	// Dependents reads the beads that have an edge of type typ onto id. Each
	// row is the dependent's own fields with the edge's type, and carries none
	// of its own edges. A read that fails returns a *ReadError, and so does an
	// id the store does not hold.
	Dependents(id, typ string) ([]Bead, error)
	// ReadyIDs reads the id of every bead the store reports ready. A read that
	// fails returns a *ReadError.
	ReadyIDs() ([]string, error)
	// SetState sets one state dimension of id to value, with reason, as one
	// `gc bd set-state`. An error is a write that did not land.
	SetState(id, dimension, value, reason string) error
	// Update makes one `gc bd update` of id with args, returning its output.
	// An error is a write that did not land.
	Update(id string, args ...string) (string, error)
	// AddEdge makes one `gc bd dep add` of an edge of type typ from id onto
	// target, returning its output. An error is a write that did not land.
	AddEdge(id, target, typ string) (string, error)
	// Create makes one `gc bd create` titled title with args, and returns the
	// new bead's id. An error may still have filed the bead: bd answers a
	// create whose commit result it lost with the same reply and exit as a
	// refusal, so the caller finds the bead before it files again.
	Create(title string, args ...string) (string, error)
}

var _ Store = (*Client)(nil)
