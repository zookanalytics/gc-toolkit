// Package source is the data-access seam for the Helm service. It defines
// the [Source] interface — the single boundary through which the service reads
// bead state — and a [SupervisorSource] that satisfies it over the Gas
// City supervisor's loopback HTTP API.
//
// DATA-ACCESS CONTRACT (hard constraint). All bead/Dolt access goes through a
// Gas City interface/API; this service NEVER opens Dolt directly (no
// sql.Open("mysql"), no JSON_EXTRACT against bead DBs). v1 uses the supervisor
// HTTP API, which is itself a Gas City API. The [Source] interface exists so a
// future contract-compliant backend (the in-process beads library, or a
// sanctioned new endpoint) can swap in without touching the model or serving
// code.
package source

import (
	"context"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// Result is one gather pass: the raw anchors that [board.BuildBoard] consumes,
// the cross-anchor joins it derives `held` and the in-flight counts from, plus
// cross-rig degradation signals propagated from the underlying API.
type Result struct {
	Anchors []board.Anchor
	// Facts are the visit / in-flight / session-liveness maps. A backend that
	// cannot supply them leaves the zero value, which yields a narrower board
	// (nothing held, nothing in flight) rather than a wrong one.
	Facts         board.Facts
	Partial       bool
	PartialErrors []string
}

// Source gathers the raw inputs for one board computation. Implementations must
// honour the data-access contract documented on the package.
type Source interface {
	Gather(ctx context.Context) (*Result, error)
}
