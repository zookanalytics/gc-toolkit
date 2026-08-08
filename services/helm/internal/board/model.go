// Package board is the Go port of the Helm board MODEL — the ranking and
// derivation logic that the bash proof-of-concept (assets/scripts/gc-helm.sh)
// computes in a single jq pass. It is deliberately free of I/O: a [Source]
// gathers raw [Anchor] data, and [BuildBoard] turns it into a ranked,
// deduplicated [Board].
//
// SPIKE SCOPE. This is the minimal subset proven by the tk-sy3vj spike. The
// per-tile fields are exactly {id, rig, kind, title, severity, n_closed,
// m_total, open, in_progress, frontier, needs, rank_score} plus the envelope
// {generated_at, total, tiles}. The following gc-helm.sh behaviours are
// deferred to a follow-up bead and intentionally NOT reproduced here:
//
//   - the full rank weight (priority + cross-rig-ref scan): the spike weight is
//     m_total + prio_w(priority); the cross-rig description scan is dropped.
//   - stale_days: the supervisor HTTP API omits updated_at, so staleness is 0
//     and the NORMAL→ELEVATED stale bump never fires.
//   - the takeaway-driven NEEDS sentence: NEEDS uses the deterministic phrase.
//   - the stranded/empty/complete/progress_mismatch booleans.
//   - the `held` visit fact (the bash board's glyph: an open visit bead with
//     task_kind=visit whose gc.continuation_group names the anchor). The
//     supervisor bead API omits metadata, so visit presence is not derivable
//     over HTTP; the field is dropped rather than approximated. (The retired
//     v1 `live` hot/warm/cold host field is gone with the host mechanism
//     itself — do not reintroduce it.)
//
// The struct tags are an additive contract: the TypeScript frontend mirrors
// them, so fields may be added but never renamed or removed.
package board

import "time"

// Severity is the attention band of a tile. Higher bands dominate ranking.
type Severity string

const (
	SevHigh     Severity = "HIGH"     // stranded: open work with none in progress
	SevElevated Severity = "ELEVATED" // a human-gated decision (or, with staleness, an aged NORMAL)
	SevNormal   Severity = "NORMAL"   // healthy in-flight work
	SevLow      Severity = "LOW"      // empty or fully closed
)

// sevRank mirrors gc-helm.sh's `def sevrank`. It is the dominant term in
// rank_score, multiplied by 1e6 so the band always outweighs the weight and
// staleness terms.
func (s Severity) rank() int {
	switch s {
	case SevHigh:
		return 3
	case SevElevated:
		return 2
	case SevNormal:
		return 1
	default: // SevLow and anything unknown
		return 0
	}
}

// Child is a rolled-up member of an anchor (epic child or convoy dependent).
// Only the status is needed for the spike counts; assignee is carried for parity
// with the model but is not surfaced (the supervisor API omits it).
type Child struct {
	ID       string `json:"id"`
	Status   string `json:"status"`
	Assignee string `json:"assignee,omitempty"`
}

// Anchor is one raw gather result before derivation — the Go analogue of a line
// in gc-helm.sh's anchors.ndjson. A [Source] produces these; [BuildBoard]
// consumes them.
type Anchor struct {
	ID       string  `json:"id"`
	Title    string  `json:"title"`
	Kind     string  `json:"kind"`   // epic | decision | convoy
	Source   string  `json:"source"` // same string as Kind; drives derivation branches
	Rig      string  `json:"rig"`
	Prefix   string  `json:"prefix"`
	Priority *int    `json:"priority,omitempty"`
	Children []Child `json:"children,omitempty"`
}

// Tile is one rendered row of the board — the additive contract mirrored by the
// frontend. Field order matches the gc-helm.sh --json object for the spike
// subset.
type Tile struct {
	ID         string   `json:"id"`
	Rig        string   `json:"rig"`
	Kind       string   `json:"kind"`
	Title      string   `json:"title"`
	Severity   Severity `json:"severity"`
	NClosed    int      `json:"n_closed"`
	MTotal     int      `json:"m_total"`
	Open       int      `json:"open"`
	InProgress int      `json:"in_progress"`
	Frontier   string   `json:"frontier"`
	Needs      string   `json:"needs"`
	RankScore  int      `json:"rank_score"`
}

// Board is the envelope returned by the service. Tiles are sorted by rank_score
// descending and deduplicated by id; Total is the count before any row cap.
type Board struct {
	GeneratedAt   time.Time `json:"generated_at"`
	Total         int       `json:"total"`
	Tiles         []Tile    `json:"tiles"`
	Partial       bool      `json:"partial,omitempty"`
	PartialErrors []string  `json:"partial_errors,omitempty"`
}
