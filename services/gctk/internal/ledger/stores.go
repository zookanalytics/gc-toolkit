package ledger

import "context"

// Opener opens a ledger over the store at db, a store's .beads directory,
// whose every read ends when ctx does. A domain that walks every rig's store
// takes one, so its tests open each store over a fake.
type Opener func(ctx context.Context, db string) (*Ledger, error)

// OpenStore is the Opener over the city's stores: the store adapter pinned to
// db ([OpenContext]).
func OpenStore(ctx context.Context, db string) (*Ledger, error) { return OpenContext(ctx, db) }
