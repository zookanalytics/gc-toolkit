package board

import (
	"fmt"
	"sort"
	"time"
)

// PackBuild is one compiled component's build state — helm-svc itself, gctk,
// anything else the pack builds out of band — as the build order last left it.
//
// WHY IT IS ON THE BOARD. Nothing in the running system builds these binaries:
// the launchers exec what a build order published, and the order runs on a
// cooldown. So a component can serve a binary older than its sources for as
// long as nobody looks, and looking meant running a one-shot script. The board
// is where the operator already looks, so the seam is surfaced there.
//
// The fields are what the build order writes; Severity and Detail are derived
// by [DerivePackHealth] so the dashboard and the CLI cannot disagree about what
// a row means.
type PackBuild struct {
	Component string `json:"component"`

	// BuiltAt is when the binary now on disk was produced, and BinaryRev the
	// revision it was built FROM. SourceRev is the revision the last build tick
	// SAW. The two revisions diverge exactly when a build failed: the tree moved
	// on, the last good binary kept serving, and that gap is the thing worth
	// showing.
	BuiltAt   time.Time `json:"built_at,omitzero"`
	SourceRev string    `json:"source_rev"`
	BinaryRev string    `json:"binary_rev"`

	// LastBuildRC is the exit status of the last build ATTEMPT, 0 for success.
	LastBuildRC int `json:"last_build_rc"`

	// RestartPending marks a published binary that nothing is running yet —
	// built, but not serving.
	RestartPending bool `json:"restart_pending"`

	// CheckedAt is when the build order last ran at all, successful build or
	// not. It is the only field that moves on a no-op tick, so it is the only
	// one that can say the builder itself has stopped.
	CheckedAt time.Time `json:"checked_at,omitzero"`

	Severity Severity `json:"severity"`
	Detail   string   `json:"detail"`
}

// buildCheckStale is how long a component may go unchecked before the row says
// the builder itself looks stopped. The build orders run on a 5m cooldown, and
// a cooldown dispatcher fires slower than it declares — one gap of ~19 minutes
// has been measured on a healthy queue — so the window is generous enough that
// ordinary lateness never speaks.
const buildCheckStale = 45 * time.Minute

// shortRev trims a revision for display without inventing one: a value that is
// not a full hash is shown as it stands.
func shortRev(rev string) string {
	if len(rev) > 12 {
		return rev[:12]
	}
	return rev
}

// DerivePackHealth bands each row and writes its one-line detail. Rows come back
// sorted by severity then component, so the order is stable across renders.
//
// The bands, most severe first:
//
//	HIGH      the last build failed, or a published binary is not serving
//	ELEVATED  the serving binary predates the tree, or nothing has checked lately
//	NORMAL    current
//	LOW       a row that says nothing — no revision was recorded at all
func DerivePackHealth(rows []PackBuild, now time.Time) []PackBuild {
	out := make([]PackBuild, 0, len(rows))
	for _, r := range rows {
		r.Severity, r.Detail = bandBuild(r, now)
		out = append(out, r)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if a, b := out[i].Severity.rank(), out[j].Severity.rank(); a != b {
			return a > b
		}
		return out[i].Component < out[j].Component
	})
	return out
}

func bandBuild(r PackBuild, now time.Time) (Severity, string) {
	// A failed build is the loudest thing this row can say, and it is louder
	// than staleness: the tree has moved somewhere the binary cannot follow.
	if r.LastBuildRC != 0 {
		if r.BinaryRev != "" {
			return SevHigh, fmt.Sprintf("last build FAILED (rc %d); still serving %s", r.LastBuildRC, shortRev(r.BinaryRev))
		}
		return SevHigh, fmt.Sprintf("last build FAILED (rc %d); nothing has ever built", r.LastBuildRC)
	}
	if r.RestartPending {
		return SevHigh, fmt.Sprintf("built %s but nothing restarted onto it — the old binary is still serving", shortRev(r.BinaryRev))
	}
	// Unchecked outranks out-of-date: if the builder stopped, every other field
	// here is a report about a moment that has passed.
	if !r.CheckedAt.IsZero() && now.Sub(r.CheckedAt) > buildCheckStale {
		return SevElevated, fmt.Sprintf("build order has not run for %s — this row is that old too", roundedAge(now.Sub(r.CheckedAt)))
	}
	if r.SourceRev != "" && r.BinaryRev != "" && r.SourceRev != r.BinaryRev {
		return SevElevated, fmt.Sprintf("serving %s, sources are at %s", shortRev(r.BinaryRev), shortRev(r.SourceRev))
	}
	if r.BinaryRev == "" {
		// Two different silences. A build order that ran without git on PATH
		// produces a record with a build time and no revision — the binary is
		// fine, but nothing here can say whether it matches the tree, and
		// calling that "current" would be a claim nobody measured.
		if !r.BuiltAt.IsZero() {
			return SevLow, fmt.Sprintf("built %s, no revision recorded — currency cannot be checked", r.BuiltAt.Format("2006-01-02T15:04Z"))
		}
		return SevLow, "no build recorded"
	}
	return SevNormal, fmt.Sprintf("current at %s", shortRev(r.BinaryRev))
}

// roundedAge renders a duration the way a status line wants it: whole minutes
// under an hour, whole hours under a day, whole days beyond.
func roundedAge(d time.Duration) string {
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}
