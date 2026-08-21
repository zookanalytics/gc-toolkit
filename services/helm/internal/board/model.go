// Package board is the Go port of the Helm board MODEL — the ranking and
// derivation logic that the bash proof-of-concept (assets/scripts/gc-helm.sh)
// computes in a single jq pass. It is deliberately free of I/O: a [Source]
// gathers raw [Anchor] data, and [BuildBoard] turns it into a ranked,
// deduplicated [Board].
//
// SCOPE. This started as the minimal subset proven by the tk-sy3vj spike and
// was widened by tk-x89rn, which restored the two raw facts the spike could not
// read — [Anchor.UpdatedAt] and [Anchor.Metadata] — and with them the real
// stale_days. The per-tile fields are {id, rig, kind, title, severity, n_closed,
// m_total, open, in_progress, frontier, needs, stale_days, updated_at,
// rank_score} plus the envelope {generated_at, total, tiles}.
//
// Carrying a fact is not the same as spending it. tk-x89rn shipped only the
// CAPABILITY — Metadata populated on every anchor and child, read by nothing —
// because its three consumers are separate beads, kept apart to stay
// reviewable. tk-2v08m has since spent it in the GATHER: `source.BeadsSource`
// selects two further anchor kinds by metadata (`human` for
// `gc.routed_to=human`, `parked` for a bead carrying `gc.takeaway`), so the
// board's KIND is no longer a synonym for the bead's issue type. No derivation
// in THIS package reads Metadata yet; the two beads that will are tk-x55wt
// (dead columns + constant NEEDS) and tk-b3rga (decision tiles). So the
// following gc-helm.sh behaviours remain NOT reproduced here:
//
//   - the full rank weight (priority + cross-rig-ref scan): the weight is
//     m_total + prio_w(priority); the cross-rig description scan is dropped.
//   - the takeaway-driven NEEDS sentence: NEEDS uses the deterministic phrase.
//   - the stranded/empty/complete/progress_mismatch booleans.
//   - the `held` visit fact (the bash board's glyph: an open visit bead with
//     task_kind=visit whose gc.continuation_group names the anchor). Metadata
//     is now readable, so this is derivable — but deriving it belongs to the
//     consumer bead, not here. (The retired v1 `live` hot/warm/cold host field
//     is gone with the host mechanism itself — do not reintroduce it.)
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
// Only the status feeds the counts today; Assignee, UpdatedAt and Metadata are
// carried for parity with the model and are what the consumer beads spend (a
// dead-owner check, per-child staleness, the visit glyph). A source that cannot
// read a field leaves it zero rather than approximating it.
type Child struct {
	ID        string            `json:"id"`
	Status    string            `json:"status"`
	Assignee  string            `json:"assignee,omitempty"`
	UpdatedAt time.Time         `json:"updated_at,omitzero"`
	Metadata  map[string]string `json:"metadata,omitempty"`
}

// Anchor is one raw gather result before derivation — the Go analogue of a line
// in gc-helm.sh's anchors.ndjson. A [Source] produces these; [BuildBoard]
// consumes them.
//
// UpdatedAt and Metadata are the two facts tk-x89rn widened the seam to carry.
// UpdatedAt drives stale_days (and through it the NORMAL→ELEVATED bump); a zero
// value means the source could not read it and staleness reads as 0, exactly as
// gc-helm.sh treats a null updated_at. Metadata is what a source SELECTS the
// `human` and `parked` kinds by; carrying it here keeps that decision auditable
// from the anchor, but no derivation reads it — see the package doc.
type Anchor struct {
	ID        string            `json:"id"`
	Title     string            `json:"title"`
	Kind      string            `json:"kind"`   // epic | decision | convoy | human | parked
	Source    string            `json:"source"` // same string as Kind; drives derivation branches
	Rig       string            `json:"rig"`
	Prefix    string            `json:"prefix"`
	Priority  *int              `json:"priority,omitempty"`
	UpdatedAt time.Time         `json:"updated_at,omitzero"`
	Metadata  map[string]string `json:"metadata,omitempty"`
	Children  []Child           `json:"children,omitempty"`
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
	// StaleDays is whole days since the anchor was last updated, and UpdatedAt
	// is the timestamp it came from. Both are 0/zero when the source cannot read
	// updated_at — indistinguishable, on the wire, from an anchor touched today.
	// That ambiguity is why UpdatedAt is carried alongside: absent means unknown,
	// present means genuinely fresh.
	StaleDays int       `json:"stale_days"`
	UpdatedAt time.Time `json:"updated_at,omitzero"`
	RankScore int       `json:"rank_score"`
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
