// Package closed is the model behind the Helm service's closed-dispositions
// view — what reached a disposition inside a window, and why.
//
// WHY IT EXISTS. The board is open-only BY CONSTRUCTION: every anchor gather in
// internal/source filters on status open, so when a sitting concludes and its
// subject closes, the row simply leaves the board. Nothing afterwards says what
// was decided. This is that answer, and it is a READ over facts sign-off already
// stamps — nothing here writes, and nothing new needed instrumenting:
//
//	gc.outcome   on the closed VISIT    the machine-readable disposition
//	                                    (routed / moot / ruled / disposed / …)
//	gc.takeaway  on the SUBJECT         the ≤140-char headline — the why
//	the `tracks` edge                   what ties the visit to its subject
//
// PULL, NOT PUSH, and that is a ruling rather than a default (operator,
// 2026-08-23: "pull, I won't read a random digest nor can we easily have a
// cadence when my schedule varies"). So this ships as a view and NOTHING else:
// no order, no cadence, no nudge, no mail. Adding any of them would invert the
// ruling the view exists to satisfy.
//
// ROWS ARE PER-VISIT, NOT PER-SUBJECT. A subject with three sittings that closed
// inside the window is three decisions and earns three rows. Collapsing to the
// subject would keep only the last one and silently drop the rest — and the
// earlier sittings are exactly the ones no other surface still shows.
//
// It is deliberately a SEPARATE model from internal/board rather than a mode on
// it. The board ranks open anchors by how much they need a human; this ranks
// nothing and answers for closed visits. Sharing a package would only share the
// word "row".
package closed

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

// DefaultSince is the window when the caller names none. A day is the span an
// operator can still reconstruct from memory, which is what makes the list
// readable rather than an archive.
const DefaultSince = 24 * time.Hour

// DefaultMaxRows caps an uncapped request, mirroring board.DefaultMaxRows. A
// window wide enough to overflow it is a window worth narrowing.
const DefaultMaxRows = 50

// Disposition is one closed sitting: a visit that ended inside the window, the
// subject it tracked, and the two facts sign-off stamped.
//
// FIELD NAMES ARE THE WIRE CONTRACT for both renderers — `helm-svc closed
// --json` emits these objects directly and the SPA mirrors them. Subject and
// SubjectTitle are both carried because an id alone is not readable and a title
// alone is not resolvable; the operator needs to recognise the row AND be able
// to go to it.
type Disposition struct {
	Rig      string    `json:"rig"`
	Visit    string    `json:"visit"`
	ClosedAt time.Time `json:"closed_at"`
	Outcome  string    `json:"outcome"`
	Subject  string    `json:"subject"`
	// SubjectTitle and Takeaway are resolved from the SUBJECT bead, which is
	// routinely still open after the sitting that disposed of it closed. Empty
	// means the subject carried none, never that the lookup failed — a failed
	// lookup marks the whole gather partial instead.
	SubjectTitle string `json:"subject_title"`
	Takeaway     string `json:"takeaway"`
}

// Dispositions is the envelope the HTTP route serves, mirroring board.Board's shape so
// a consumer of one can read the other without learning a second convention.
// The CLI emits Dispositions.Rows as a bare array instead, exactly as `helm-svc board
// --json` emits tiles rather than the envelope.
//
// Cutoff rides the wire beside Since because "the last 24h" is ambiguous about
// which 24 hours: an operator comparing two glances needs the absolute instant
// the window opened, not just its width.
//
// THERE IS NO `partial` FIELD, and its absence is the contract. board.Board
// carries one because a board missing a rig is still a true statement about the
// rigs it read — the rows shown mean what they say. Here a short list does not
// mean what it says: the whole question is "what was decided", and an answer
// that quietly omits a wedged rig's dispositions is indistinguishable from a
// genuinely quiet window. So a gather that cannot read everything it was asked
// for returns an ERROR and renders nothing; see [source.ClosedSource].
type Dispositions struct {
	GeneratedAt time.Time `json:"generated_at"`
	Since       string    `json:"since"`
	Cutoff      time.Time `json:"cutoff"`
	// Total is the row count BEFORE the cap, so a capped list can say how much
	// it is not showing.
	Total int           `json:"total"`
	Rows  []Disposition `json:"rows"`
}

// Input is one Build call's arguments. It is a struct rather than a parameter
// list because the two renderers must pass the same five things and a
// positional call of that width invites a silent transposition.
type Input struct {
	Rows   []Disposition
	Now    time.Time
	Since  string
	Cutoff time.Time
	Limit  int // 0 = uncapped
}

// Build orders the rows newest-first, caps them, and wraps them in the envelope.
//
// It never drops a row for being incomplete. A closed visit is terminal whether
// or not sign-off stamped an outcome on it, and dropping the unstamped ones
// would hide exactly the dispositions whose record is worth seeing.
func Build(in Input) Dispositions {
	rows := make([]Disposition, len(in.Rows))
	copy(rows, in.Rows)
	sortRows(rows)

	total := len(rows)
	if in.Limit > 0 && len(rows) > in.Limit {
		rows = rows[:in.Limit]
	}
	if rows == nil {
		// `[]`, never `null`: a consumer running `jq 'length'` over this must
		// read an empty window as empty, not as an error.
		rows = []Disposition{}
	}
	return Dispositions{
		GeneratedAt: in.Now,
		Since:       in.Since,
		Cutoff:      in.Cutoff,
		Total:       total,
		Rows:        rows,
	}
}

// sortRows orders newest close first. The visit id is the tie-break so a batch
// of visits closed in the same second renders in a stable order — without it
// two glances at an unchanged store could disagree about the row order, which
// reads as movement that did not happen.
func sortRows(rows []Disposition) {
	sort.SliceStable(rows, func(i, j int) bool {
		if !rows[i].ClosedAt.Equal(rows[j].ClosedAt) {
			return rows[i].ClosedAt.After(rows[j].ClosedAt)
		}
		return rows[i].Visit < rows[j].Visit
	})
}

// ParseSince converts a window spec to a duration, the way this pack spells
// durations everywhere else (assets/scripts/gc-bd-watch.sh): "30s", "90m",
// "24h", "7d", or a bare integer meaning seconds.
//
// THE SPELLING IS VALIDATED, NOT COERCED, and that is the whole point of having
// this as a function. The shell original parsed with awk's int(), which reads
// "2w" as 2 — so an unsupported unit silently became two SECONDS, a window
// three orders of magnitude short that renders as a plausible-looking empty
// result. Go's strconv refuses the same input outright, and this refuses every
// other near-miss (a negative, a fraction, a bare unit) for the same reason: on
// this surface a wrong window and a quiet window are indistinguishable.
//
// Zero is refused rather than defaulted. A caller that wants the default omits
// the flag; one that passes "0" is asking for an empty window, which is never
// what they meant.
func ParseSince(spec string) (time.Duration, error) {
	s := strings.TrimSpace(spec)
	if s == "" {
		return 0, fmt.Errorf("--since must be a duration like 24h, 90m, 7d, 30s, or bare seconds (got %q)", spec)
	}

	unit := time.Second
	digits := s
	switch s[len(s)-1] {
	case 's':
		unit, digits = time.Second, s[:len(s)-1]
	case 'm':
		unit, digits = time.Minute, s[:len(s)-1]
	case 'h':
		unit, digits = time.Hour, s[:len(s)-1]
	case 'd':
		unit, digits = 24*time.Hour, s[:len(s)-1]
	}

	// Atoi refuses "", "-1", "1.5", "2w" (the 'w' is not a unit above, so it
	// stays in the digits) and any other spelling this pack does not define.
	n, err := strconv.Atoi(digits)
	if err != nil || n <= 0 {
		return 0, fmt.Errorf("--since must be a positive duration like 24h, 90m, 7d, 30s, or bare seconds (got %q)", spec)
	}
	return time.Duration(n) * unit, nil
}
