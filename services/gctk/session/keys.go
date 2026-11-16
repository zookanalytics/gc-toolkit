package session

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys the domain reads, each written by Gas City, so each is declared
// read-only here. The two on a bead are runtime-owned in
// lifecycle/lifecycle.toml ([metadata.runtime_owned]), and the two on a
// session's own bead are Gas City's record of the session, which the pack
// never writes.
var (
	sessionIDKey = ledger.ReadOnly("gc.session_id", ledger.String,
		"The session that claimed a bead, written by Gas City's claim and left by its release "+
			"(lifecycle/lifecycle.toml, [metadata.runtime_owned]). The session domain reads it as the first "+
			"identity a bead names its owner by, and the seat-progress look as the seat a claim belongs to.")
	sessionNameKey = ledger.ReadOnly("gc.session_name", ledger.String,
		"The runtime name of the session that holds a bead, written by Gas City beside gc.session_id "+
			"(lifecycle/lifecycle.toml, [metadata.runtime_owned]). The session domain reads it as an identity "+
			"a bead names its owner by.")
	poolManagedKey = ledger.ReadOnly("pool_managed", ledger.String,
		"true on the bead of a session Gas City runs as a pool seat, which its work ladder paces "+
			"(ladderGoverns in cmd/gc/work_ladder_lane.go at gastownhall/gascity c7eb6d2f43). The "+
			"seat-progress look judges only such a seat.")
	lastWokeAtKey = ledger.ReadOnly("last_woke_at", ledger.String,
		"When a session last woke, RFC 3339 in UTC, which Gas City writes on its session bead at each wake "+
			"and clears when it stops (internal/session/lifecycle_transition.go at gastownhall/gascity "+
			"c7eb6d2f43). The seat-progress look counts a seat's silence from no earlier than it, so a seat "+
			"restarted in place is judged only on the time it has run.")
)
