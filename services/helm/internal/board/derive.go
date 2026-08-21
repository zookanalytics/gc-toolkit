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

// staleThresholdDays mirrors gc-helm.sh's STALE_DAYS=14: a NORMAL anchor
// untouched for MORE than this many days is bumped to ELEVATED.
const staleThresholdDays = 14

// staleDays is whole days since updatedAt, mirroring gc-helm.sh line 769
// (`(($now - $upd) / 86400) | floor`). A zero updatedAt means the source could
// not read the field, which the bash treats as `$upd == null` → 0.
//
// The result is floored at 0. A negative value — a future updated_at, from clock
// skew between the writer and this process — occupies the units lane of
// rank_score, where it would borrow from the weight lane and could invert the
// band ordering the lane packing exists to guarantee. gc-helm.sh does not floor;
// it also does not run against a clock it did not set.
//
// There is deliberately no UPPER clamp here: rankScore caps its own term, so
// capping the reported value too would only lie to the reader about how old an
// ancient anchor is. The tile reports the real age; the rank lane stays bounded.
func staleDays(updatedAt, now time.Time) int {
	if updatedAt.IsZero() {
		return 0
	}
	return max(int(now.Sub(updatedAt)/(24*time.Hour)), 0)
}

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
// with none in progress. The stale bump (NORMAL→ELEVATED when stale>14) fires
// on a real stale, which an anchor with an unreadable updated_at never reaches:
// staleness there is 0, so an unknown age is treated as fresh rather than
// silently promoted.
//
// The two metadata-gathered kinds (tk-2v08m) sit at opposite ends on purpose. A
// `human` bead is ELEVATED for the same reason a decision is: it is stamped
// `gc.routed_to=human`, so no agent will take it and it moves only when the
// operator moves it. A `parked` bead is LOW because it is the opposite claim —
// the conversation reached a takeaway and wants nothing, it just has to stay
// FINDABLE. Ranking it against stranded epics is what the bead asks not to do,
// and LOW is how it stays out of that contest: the band floor puts every parked
// row beneath every real attention item, whatever its priority or age.
func severity(src string, mTotal, open, inProgress, stale int) Severity {
	var sev0 Severity
	switch {
	// These three kinds carry no roll-up by construction — the gather admits
	// the bead itself, not a set it owns — so the band comes from what the bead
	// IS. Falling through to the count branches below would read every one of
	// them as an empty anchor and file it under LOW.
	case src == "decision", src == "human":
		sev0 = SevElevated
	case src == "parked":
		sev0 = SevLow
	case mTotal == 0:
		sev0 = SevLow
	case open == 0:
		sev0 = SevLow
	case open > 0 && inProgress == 0:
		sev0 = SevHigh
	default:
		sev0 = SevNormal
	}
	if sev0 == SevNormal && stale > staleThresholdDays {
		return SevElevated
	}
	return sev0
}

// rankScore reproduces line 672: sevrank*1e6 + weight*1e3 + min(stale,999). The
// weight is m_total + prio_w(priority) (the cross-rig-ref term is deferred).
// weight is capped so it can never bleed into the severity lane; stale arrives
// already clamped to the units lane by [staleDays].
func rankScore(sev Severity, mTotal int, priority *int, stale int) int {
	weight := min(mTotal+prioWeight(priority), rankTermCap)
	return sev.rank()*rankSeverityMultiplier +
		weight*rankWeightMultiplier +
		min(stale, rankTermCap)
}

// frontier is the one-line human summary. Display-only; it does
// not feed rank_score. The metadata-gathered kinds describe their own state
// rather than a roll-up they do not have.
func frontier(a Anchor, mTotal, open, inProgress int) string {
	switch {
	case a.Source == "decision":
		return "human-gated decision"
	case a.Source == "human":
		return "routed to the operator — no agent will take it"
	case a.Source == "parked":
		return "conversation parked — takeaway recorded"
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
// leading takeaway branch of gc-helm.sh is intentionally omitted here — a
// `parked` bead names the resume GESTURE, not what its takeaway said, because
// deriving a sentence from `gc.takeaway` is tk-x55wt's bead, not this one.
//
// The gesture is real: `gc-visit-open` resolves a bare bead id against the live
// rig prefixes and reopens the conversation on that bead, which is what the
// prefix+a popup feeds it (assets/scripts/tmux-visit-prompt.sh). Resume already
// worked before this change; only finding the id did not.
func needs(a Anchor, mTotal, open, inProgress int) string {
	switch {
	case a.Source == "decision":
		return "operator decision"
	case a.Source == "human":
		return "operator action"
	case a.Source == "parked":
		return "resume: prefix+a, then the bead id"
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

// computeTile derives a single tile from an anchor. now is the board's
// generation instant, shared by every tile so one board never mixes staleness
// measured against two different clock reads.
func computeTile(a Anchor, now time.Time) Tile {
	mTotal, nClosed, open, inProgress := counts(a.Children)
	stale := staleDays(a.UpdatedAt, now)
	sev := severity(a.Source, mTotal, open, inProgress, stale)

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
		StaleDays:  stale,
		UpdatedAt:  a.UpdatedAt,
		RankScore:  rankScore(sev, mTotal, a.Priority, stale),
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
		tiles = append(tiles, computeTile(a, now))
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
