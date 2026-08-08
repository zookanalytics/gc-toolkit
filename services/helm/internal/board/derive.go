package board

import (
	"fmt"
	"sort"
	"time"
)

// rankSeverityMultiplier and rankWeightMultiplier keep the three rank_score
// terms in non-overlapping decimal lanes, exactly as gc-helm.sh does:
// severity (0-3) * 1e6 dominates, weight (capped < 1000) * 1e3 is the middle
// term, and the staleness tiebreaker (capped at 999) occupies the units. The
// caps below preserve that invariant.
const (
	rankSeverityMultiplier = 1_000_000
	rankWeightMultiplier   = 1_000
	rankTermCap            = 999
)

// staleDays is 0 for the spike: the supervisor HTTP API omits updated_at, so the
// staleness tiebreaker and the NORMAL→ELEVATED stale bump cannot be computed.
// The follow-up bead reintroduces this from a richer source.
const staleDays = 0

// prioWeight mirrors gc-helm.sh's `def prio_w($p)`: max(0, 4-priority),
// with a nil/absent priority treated as the gather default (priority 3 → 1).
// P1→3, P2→2, P3→1, P4→0.
func prioWeight(priority *int) int {
	if priority == nil {
		return 1
	}
	return max(0, 4-*priority)
}

// counts derives the four child-status counts (lines 592-601 of gc-helm.sh).
// open counts every non-closed child (including blocked/deferred); inProgress is
// strictly status=="in_progress".
func counts(children []Child) (mTotal, nClosed, open, inProgress int) {
	mTotal = len(children)
	for _, c := range children {
		switch c.Status {
		case "closed":
			nClosed++
		case "in_progress":
			inProgress++
			open++
		default:
			open++
		}
	}
	return mTotal, nClosed, open, inProgress
}

// severity mirrors gc-helm.sh's band derivation. STRANDED (HIGH) is open work
// with none in progress. The stale bump (NORMAL→ELEVATED when stale>14)
// is a no-op in the spike because staleDays is 0, but is kept structurally so the
// follow-up only has to supply a real staleDays.
func severity(src string, mTotal, open, inProgress int) Severity {
	var sev0 Severity
	switch {
	case src == "decision":
		sev0 = SevElevated
	case mTotal == 0:
		sev0 = SevLow
	case open == 0:
		sev0 = SevLow
	case open > 0 && inProgress == 0:
		sev0 = SevHigh
	default:
		sev0 = SevNormal
	}
	if sev0 == SevNormal && staleDays > 14 {
		return SevElevated
	}
	return sev0
}

// rankScore reproduces line 672: sevrank*1e6 + weight*1e3 + min(stale,999). The
// spike weight is m_total + prio_w(priority) (the cross-rig-ref term is
// deferred). weight is capped so it can never bleed into the severity lane.
func rankScore(sev Severity, mTotal int, priority *int) int {
	weight := min(mTotal+prioWeight(priority), rankTermCap)
	return sev.rank()*rankSeverityMultiplier +
		weight*rankWeightMultiplier +
		min(staleDays, rankTermCap)
}

// frontier is the one-line human summary. Display-only; it does
// not feed rank_score.
func frontier(a Anchor, mTotal, open, inProgress int) string {
	switch {
	case a.Source == "decision":
		return "human-gated decision"
	case mTotal == 0:
		return "empty — no children"
	case open == 0:
		return fmt.Sprintf("all %d closed · 0 open", mTotal)
	case inProgress == 0:
		return fmt.Sprintf("%d open · 0 in-progress (stranded)", open)
	default:
		return fmt.Sprintf("%d open · %d in-progress", open, inProgress)
	}
}

// needs is the "what does a human do" hint, using the
// deterministic phrase only. The takeaway-driven sentence is deferred, so the
// leading takeaway branch of gc-helm.sh is intentionally omitted here.
func needs(a Anchor, mTotal, open, inProgress int) string {
	switch {
	case a.Source == "decision":
		return "operator decision"
	case mTotal == 0:
		return "no children — decompose or assign"
	case open == 0:
		if a.Source == "convoy" {
			return fmt.Sprintf("all %d closed — graduate", mTotal)
		}
		return fmt.Sprintf("all %d closed — close or extend", mTotal)
	case inProgress == 0:
		return "decomposed, idle — assign or visit"
	default:
		return "in flight"
	}
}

// computeTile derives a single tile from an anchor.
func computeTile(a Anchor) Tile {
	mTotal, nClosed, open, inProgress := counts(a.Children)
	sev := severity(a.Source, mTotal, open, inProgress)

	return Tile{
		ID:         a.ID,
		Rig:        a.Rig,
		Kind:       a.Kind,
		Title:      a.Title,
		Severity:   sev,
		NClosed:    nClosed,
		MTotal:     mTotal,
		Open:       open,
		InProgress: inProgress,
		Frontier:   frontier(a, mTotal, open, inProgress),
		Needs:      needs(a, mTotal, open, inProgress),
		RankScore:  rankScore(sev, mTotal, a.Priority),
	}
}

// BuildBoard derives every tile, ranks by rank_score descending, and
// deduplicates by id keeping the highest-ranked occurrence (so a bead matched
// by two gathers appears once, in its higher band). Ties break by id ascending
// for deterministic output. now stamps
// GeneratedAt. partial/partialErrors propagate cross-rig degradation.
func BuildBoard(anchors []Anchor, now time.Time, partial bool, partialErrors []string) Board {
	tiles := make([]Tile, 0, len(anchors))
	for _, a := range anchors {
		tiles = append(tiles, computeTile(a))
	}

	sort.SliceStable(tiles, func(i, j int) bool {
		if tiles[i].RankScore != tiles[j].RankScore {
			return tiles[i].RankScore > tiles[j].RankScore
		}
		return tiles[i].ID < tiles[j].ID
	})

	seen := make(map[string]struct{}, len(tiles))
	deduped := make([]Tile, 0, len(tiles))
	for _, t := range tiles {
		if _, dup := seen[t.ID]; dup {
			continue
		}
		seen[t.ID] = struct{}{}
		deduped = append(deduped, t)
	}

	return Board{
		GeneratedAt:   now.UTC(),
		Total:         len(deduped),
		Tiles:         deduped,
		Partial:       partial,
		PartialErrors: partialErrors,
	}
}
