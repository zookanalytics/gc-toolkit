package cli

import (
	"fmt"
	"io"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// The port of assets/scripts/pace-lib.sh for the two groups `gctk merge` walks:
// the anchors it visits first, which are never paced, and the rest, which
// rotate. An arm whose cost grows with the gating set runs under a pass
// budget, and an arm stopped part-way that started at the same anchor next pass
// would revisit the head of its list forever while the tail went unvisited. So
// the rest are visited in id order starting after the last one finished,
// wrapping, and each is recorded as it finishes. Every anchor is then reached
// within a bounded number of passes, whether a pass ended at its deadline or
// was killed mid-anchor. pace-lib.sh's `first` group, a rotation of its own
// ahead of the rest, is pr-open's and has no counterpart here.

// pacer walks the rest group: pace_start, pace_visit and pace_end over one
// cursor and one deadline.
type pacer struct {
	cursor string
	stderr io.Writer
	// deadline is epoch seconds, and paced is false when the pass has none: no
	// --deadline, or one that is not epoch seconds.
	deadline int64
	paced    bool
	// visited counts the anchors the walk visited (PACE_VISITED). finished is
	// the one in hand, recorded once the next visit begins. resumeAt is the
	// anchor the deadline stopped the walk at, if it did.
	visited  int
	finished string
	resumeAt string
	warned   bool
}

// newPacer is pace_start. A deadline that is not epoch seconds leaves the walk
// unpaced, and says so once; an empty one is no deadline at all.
func newPacer(cursor, deadline string, stderr io.Writer) *pacer {
	p := &pacer{cursor: cursor, stderr: stderr}
	if deadline == "" {
		return p
	}
	if strings.Trim(deadline, "0123456789") != "" {
		fmt.Fprintf(stderr, "%s: WARN --deadline '%s' is not epoch seconds; this pass is not paced\n", mergeProg, deadline)
		return p
	}
	p.paced = true
	n, err := strconv.ParseInt(deadline, 10, 64)
	if err != nil {
		// Digits too many for an int64 name a deadline no clock reaches.
		n = math.MaxInt64
	}
	p.deadline = n
	return p
}

// spent is pace_spent: true once the clock reaches the deadline.
func (p *pacer) spent() bool {
	return p.paced && time.Now().Unix() >= p.deadline
}

// visit is pace_visit for a rest anchor, called after the free skips and before
// the first read that costs. The anchor in hand has finished once the next
// visit begins. One anchor is always visited, so a walk started past its
// deadline still makes progress. visit reports false when the deadline stops
// the walk, and the anchor it stopped at is where the next pass resumes.
func (p *pacer) visit(id string) bool {
	p.flush()
	if p.visited > 0 && p.spent() {
		p.resumeAt = id
		return false
	}
	p.visited++
	p.finished = id
	return true
}

// end is pace_end: the anchor in hand when the walk ends has finished.
func (p *pacer) end() { p.flush() }

func (p *pacer) flush() {
	if p.finished == "" {
		return
	}
	p.record(p.finished)
	p.finished = ""
}

// record is pace_note, warning once when the cursor cannot be written. An empty
// cursor path records nothing.
func (p *pacer) record(id string) {
	if p.cursor == "" {
		return
	}
	tmp := p.cursor + ".tmp"
	err := os.WriteFile(tmp, []byte(id+"\n"), 0o666)
	if err == nil {
		err = os.Rename(tmp, p.cursor)
	}
	if err == nil {
		return
	}
	if !p.warned {
		fmt.Fprintf(p.stderr, "%s: WARN cannot record progress in %s; the next pass starts the rotation over\n", mergeProg, p.cursor)
	}
	p.warned = true
}

// paceOrder is pace_order: the rows in id order, starting after the id the
// cursor file names and wrapping. An absent or unreadable cursor file starts at
// the lowest id. With no cursor path the rows keep the order they came in.
func paceOrder(rows []*gcbd.Bead, cursor string) []*gcbd.Bead {
	if cursor == "" {
		return rows
	}
	after := ""
	if raw, err := os.ReadFile(cursor); err == nil {
		after, _, _ = strings.Cut(string(raw), "\n")
	}
	sorted := append([]*gcbd.Bead(nil), rows...)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].ID < sorted[j].ID })
	out := make([]*gcbd.Bead, 0, len(sorted))
	for _, r := range sorted {
		if r.ID > after {
			out = append(out, r)
		}
	}
	for _, r := range sorted {
		if r.ID <= after {
			out = append(out, r)
		}
	}
	return out
}
