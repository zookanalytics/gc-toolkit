// Package epic answers which closes and shifts of a rig's epics the rig's po
// has not weighed yet (docs/epics.md). The po weighs each one at its portfolio
// sync, since a close or a shift can change what the rig works on and in what
// order, and it marks each epic it weighs, in the sync's note on the epic, with
// the time of the read it weighed from (skills/portfolio-sync/SKILL.md). An
// epic answers by its own mark, so a sitting that ends before it marks every
// epic leaves the rest for the next sync.
//
// A close is the epic's own: its close time and reason. A shift is a ruling on
// the epic's hypothesis, which an epic review records in the epic's ruling keys
// (skills/converse-epic-review/SKILL.md). Those keys hold only the latest
// ruling, so the review also stamps the time of a shift in a key that a later
// ruling leaves standing, and a shift a later review continued still reads.
package epic

import (
	"cmp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The keys an epic's question reads. Shell writes each of them, so each is
// declared read-only, and its definition stays in lifecycle/lifecycle.toml's
// [metadata.epic_stewardship]: the epic review writes the ruling's keys and the
// shift's time, the filer the hypothesis, and the portfolio sync's note the
// mark.
var (
	hypothesisKey = ledger.ReadOnly("epic_hypothesis", ledger.String,
		"An epic's one-sentence hypothesis (docs/epics.md). An epic under an epic that carries none is a Delivery.")
	rulingKey = ledger.ReadOnly("epic_ruling", ledger.String,
		"The latest ruling on an epic's hypothesis: continue, shift or close (docs/epics.md).")
	rulingReasonKey = ledger.ReadOnly("epic_ruling_reason", ledger.String,
		"Why the latest ruling on an epic was made, written with it.")
	rulingAtKey = ledger.ReadOnly("epic_ruling_at", ledger.String,
		"When the operator made the latest ruling on an epic.")
	shiftedAtKey = ledger.ReadOnly("epic_shifted_at", ledger.String,
		"When the operator last ruled shift on an epic, written with that ruling and left standing by a later one, "+
			"so a shift a later ruling followed still reads (skills/converse-epic-review/SKILL.md). An epic that "+
			"carries none records no shift beyond its ruling keys.")
	weighedAtKey = ledger.ReadOnly("epic_weighed_at", ledger.String,
		"The time of the read the rig's po last weighed an epic from at a portfolio sync, the time gctk epic "+
			"unweighed prints first, written with the sync's note on the epic (skills/portfolio-sync/SKILL.md). "+
			"An epic that carries none has not been weighed.")
)

// The kinds of change a portfolio sync weighs.
const (
	Closed  = "closed"
	Shifted = "shifted"
)

// shift is the ruling that changes an epic's course.
const shift = "shift"

// A Change is one close or one shift of an epic that no portfolio sync has
// weighed.
type Change struct {
	// Epic is the epic's id.
	Epic string
	// Kind is Closed or Shifted.
	Kind string
	// At is when it happened, as the store or the ruling writes the time: the
	// epic's close time, or the shift ruling's time.
	At string
	// Reason is the close's reason, or the epic's latest ruling's: the shift's,
	// or the one Then names.
	Reason string
	// Then is the ruling that followed a shift, continue or close, and ThenOn
	// the UTC day the operator made it, "" when its time names none. Both are
	// empty for a close, and for a shift that is the epic's latest ruling.
	Then, ThenOn string
	// Weighed is the UTC day, YYYY-MM-DD, of the read a portfolio sync last
	// weighed the epic from, "" when none has.
	Weighed string
}

// Unweighed returns, oldest first, each close and each latest shift of the
// epics the store holds that no portfolio sync has weighed: each one made on or
// after the day a sync last weighed its epic, or every one when none has. A
// mark carries the time of the read the sync weighed the epic from, so a change
// after that read lists. One made earlier on the mark's day lists again. That
// keeps a change the read did not show though its time comes before the read,
// since a change's writer stamps its time before the write lands. One made on
// the day before the read and written after it does not list, which takes a
// single write that spans both the read and midnight UTC.
//
// An epic's latest shift is its latest ruling when that is a shift, and the
// shift's own time once a later ruling followed it, so a shift a later review
// continued lists with that ruling.
//
// A Delivery is left out: an epic whose parent is one of the store's epics and
// that carries no hypothesis, as the epic-close doctor reads one. Its close is
// one of the writes of its epic's ruling. A template and a bead the store keeps
// in its ephemeral plane are no epic of the rig's, as the store's own listing
// of epics leaves them out.
//
// A read that fails returns its *ledger.ReadError and no change, so a caller
// never takes a store that did not answer for one where nothing changed.
func Unweighed(l *ledger.Ledger) ([]Change, error) {
	recs, err := l.Find(ledger.Typed("epic").WithClosed())
	if err != nil {
		return nil, err
	}
	var epics []*ledger.Record
	ids := map[string]bool{}
	for _, r := range recs {
		if r.Template() || r.EphemeralPlane() {
			continue
		}
		epics = append(epics, r)
		ids[r.ID] = true
	}
	var out []Change
	for _, r := range epics {
		delivery, err := isDelivery(r, ids)
		if err != nil {
			return nil, err
		}
		if delivery {
			continue
		}
		changes, err := unweighed(r)
		if err != nil {
			return nil, err
		}
		out = append(out, changes...)
	}
	slices.SortStableFunc(out, func(a, b Change) int {
		return cmp.Or(instant(a.At).Compare(instant(b.At)), cmp.Compare(a.At, b.At),
			cmp.Compare(a.Epic, b.Epic), cmp.Compare(a.Kind, b.Kind))
	})
	return out, nil
}

// isDelivery reports whether r is a Delivery: no hypothesis, and a parent among
// the store's epics.
func isDelivery(r *ledger.Record, epics map[string]bool) (bool, error) {
	if hyp, _, err := hypothesisKey.Get(r); err != nil || hyp != "" {
		return false, err
	}
	parents, err := r.Parents()
	if err != nil {
		return false, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	return slices.ContainsFunc(parents, func(p string) bool { return epics[p] }), nil
}

// unweighed is r's close and its latest shift, each when made on or after the
// day of its mark, or when it carries none.
func unweighed(r *ledger.Record) ([]Change, error) {
	var err error
	get := func(k ledger.Key[string]) string {
		v, _, e := k.Get(r)
		err = cmp.Or(err, e)
		return v
	}
	mark, ruling, rulingAt, reason, shiftedAt := get(weighedAtKey), get(rulingKey), get(rulingAtKey),
		get(rulingReasonKey), get(shiftedAtKey)
	if err != nil {
		return nil, err
	}
	weighed := day(mark)
	since := func(at string) bool { d := day(at); return weighed == "" || d == "" || d >= weighed }

	var out []Change
	if r.Status() == "closed" && since(r.ClosedAt()) {
		out = append(out, Change{Epic: r.ID, Kind: Closed, At: r.ClosedAt(), Reason: r.CloseReason(), Weighed: weighed})
	}
	c := Change{Epic: r.ID, Kind: Shifted, Reason: reason, Weighed: weighed}
	switch {
	case ruling == shift:
		c.At = rulingAt
	case shiftedAt != "":
		c.At, c.Then, c.ThenOn = shiftedAt, ruling, day(rulingAt)
	default:
		return out, nil
	}
	if since(c.At) {
		out = append(out, c)
	}
	return out, nil
}

// day is the UTC day, YYYY-MM-DD, of a time as the store or a write stamps one,
// "" for one that names no day.
func day(at string) string {
	at = strings.TrimSpace(at)
	if t, err := time.Parse(time.RFC3339, at); err == nil {
		return t.UTC().Format(time.DateOnly)
	}
	if len(at) >= len(time.DateOnly) {
		if _, err := time.Parse(time.DateOnly, at[:len(time.DateOnly)]); err == nil {
			return at[:len(time.DateOnly)]
		}
	}
	return ""
}

// instant is the time at names, the zero time for one that names none.
func instant(at string) time.Time {
	t, _ := time.Parse(time.RFC3339, strings.TrimSpace(at))
	return t
}
