package epic

import (
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// keys is a row's metadata: pairs of a key and its value, over base.
func keys(base map[string]string, kv ...string) map[string]string {
	m := map[string]string{}
	for k, v := range base {
		m[k] = v
	}
	for i := 0; i+1 < len(kv); i += 2 {
		m[kv[i]] = kv[i+1]
	}
	return m
}

// ruled is the metadata an epic review's ruling leaves over base: the ruling,
// its time and its reason.
func ruled(base map[string]string, ruling, at, reason string) map[string]string {
	return keys(base, "epic_ruling", ruling, "epic_ruling_at", at, "epic_ruling_reason", reason)
}

// epicBead is an epic's row: its status, its keys and its parent, when it has
// one.
func epicBead(id, status string, meta map[string]string, parent ...string) fake.Bead {
	b := fake.Bead{ID: id, Title: id, Status: status, IssueType: "epic", Metadata: meta}
	for _, p := range parent {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeParentChild, ID: p})
	}
	return b
}

// closed is b closed at at with reason.
func closed(b fake.Bead, at, reason string) fake.Bead {
	b.Status, b.ClosedAt, b.CloseReason = "closed", at, reason
	return b
}

// lines is each change as the test compares it: its time, its epic, its kind,
// its reason, the ruling that followed it and its day, and the day its epic was
// weighed.
func lines(changes []Change) []string {
	out := make([]string, len(changes))
	for i, c := range changes {
		out[i] = strings.Join([]string{c.At, c.Epic, c.Kind, c.Reason, c.Then, c.ThenOn, c.Weighed}, " | ")
	}
	return out
}

func unweighedOn(t *testing.T, s *fake.Store) []string {
	t.Helper()
	got, err := Unweighed(ledger.New(s))
	if err != nil {
		t.Fatalf("Unweighed: %v", err)
	}
	return lines(got)
}

func sameLines(t *testing.T, what string, got, want []string) {
	t.Helper()
	if !slices.Equal(got, want) {
		t.Errorf("%s:\n got  %q\n want %q", what, got, want)
	}
}

// hyp is an epic's hypothesis, which tells an epic under an epic from a
// Delivery.
var hyp = map[string]string{"epic_hypothesis": "for whom, what changes, and the signal"}

// rig is a rig's epics, each answering by its own mark, with marks or with
// none:
//   - e1 shifted on the day of its mark, which lists again, and carries no
//     shift's own time, as a shift ruled before the review kept one.
//   - e2 was marked, and a review that continued it after its mark lists
//     nothing.
//   - e3 shifted twice and was never weighed, so its latest shift lists.
//   - e4 shifted and was continued before its mark.
//   - e5 shifted and then closed, never weighed, so it lists both.
//   - e6 closed before its mark.
//   - e7 closed on the day of its mark, which lists again.
//   - e8 shifted after its mark and a later review continued it, so its latest
//     ruling is continue and its shift was never weighed.
//   - p1 was marked when a sync parked it, and shifted after.
//   - d1 is a Delivery, an epic under an epic with no hypothesis of its own.
//   - c1, an epic under an epic with a hypothesis of its own, closed.
//   - o1 closed under a parent that is none of the rig's epics, so it is no
//     Delivery.
func rig(marked bool) *fake.Store {
	mark := func(m map[string]string, at string) map[string]string {
		if marked {
			m["epic_weighed_at"] = at
		}
		return m
	}
	s := fake.New()
	s.Put(epicBead("e1", "open", mark(ruled(hyp, "shift", "2026-11-13T09:00:00Z", "re-aimed the same day"), "2026-11-13T12:00:00Z")))
	s.Put(epicBead("e2", "open", mark(ruled(hyp, "continue", "2026-11-15T01:00:00Z", "on course"), "2026-11-14T08:00:00Z")))
	s.Put(epicBead("e3", "open", keys(ruled(hyp, "shift", "2026-11-15T02:00:00Z", "re-aimed"), "epic_shifted_at", "2026-11-15T02:00:01Z")))
	s.Put(epicBead("e4", "open", mark(keys(ruled(hyp, "continue", "2026-11-12T00:00:00Z", "held"),
		"epic_shifted_at", "2026-11-11T00:00:00Z"), "2026-11-13T10:00:00Z")))
	s.Put(closed(epicBead("e5", "open", keys(ruled(hyp, "close", "2026-11-15T02:59:00Z", "held"),
		"epic_shifted_at", "2026-11-14T05:00:00Z")), "2026-11-15T03:00:00Z", "held"))
	s.Put(closed(epicBead("e6", "open", mark(ruled(hyp, "close", "2026-11-09T23:00:00Z", "old close"), "2026-11-13T10:00:00Z")),
		"2026-11-10T00:00:00Z", "old close"))
	s.Put(closed(epicBead("e7", "open", mark(ruled(hyp, "close", "2026-11-14T00:20:00Z", "same day"), "2026-11-14T09:00:00Z")),
		"2026-11-14T00:30:00Z", "same day"))
	s.Put(epicBead("e8", "open", mark(keys(ruled(hyp, "continue", "2026-11-12T00:00:00Z", "on the new course"),
		"epic_shifted_at", "2026-11-11T00:00:00Z"), "2026-11-10T10:00:00Z")))
	s.Put(epicBead("p1", "open", mark(ruled(hyp, "shift", "2026-11-15T06:00:00Z", "shifted once parked"), "2026-11-13T10:00:00Z")))
	s.Put(closed(epicBead("d1", "open", nil, "e5"), "2026-11-15T03:30:00Z", "checkpoint"))
	s.Put(closed(epicBead("c1", "open", ruled(hyp, "close", "2026-11-15T03:59:00Z", "answered"), "e5"),
		"2026-11-15T04:00:00Z", "answered"))
	s.Put(fake.Bead{ID: "t1", Title: "a task", Status: "open", IssueType: "task"})
	s.Put(closed(epicBead("o1", "open", ruled(nil, "close", "2026-11-15T04:59:00Z", "under a task"), "t1"),
		"2026-11-15T05:00:00Z", "under a task"))
	return s
}

// Each epic answers by its own mark: its close and its latest shift list when
// made on or after the day of the epic's own mark, whatever its latest ruling,
// and when it carries none. Deliveries are left out, as the epic-close doctor
// reads one.
func TestUnweighedListsWhatNoSyncWeighedOfEachEpic(t *testing.T) {
	sameLines(t, "the changes no sync weighed", unweighedOn(t, rig(true)), []string{
		"2026-11-11T00:00:00Z | e8 | shifted | on the new course | continue | 2026-11-12 | 2026-11-10",
		"2026-11-13T09:00:00Z | e1 | shifted | re-aimed the same day |  |  | 2026-11-13",
		"2026-11-14T00:30:00Z | e7 | closed | same day |  |  | 2026-11-14",
		"2026-11-14T05:00:00Z | e5 | shifted | held | close | 2026-11-15 | ",
		"2026-11-15T02:00:00Z | e3 | shifted | re-aimed |  |  | ",
		"2026-11-15T03:00:00Z | e5 | closed | held |  |  | ",
		"2026-11-15T04:00:00Z | c1 | closed | answered |  |  | ",
		"2026-11-15T05:00:00Z | o1 | closed | under a task |  |  | ",
		"2026-11-15T06:00:00Z | p1 | shifted | shifted once parked |  |  | 2026-11-13",
	})
}

// A rig no sync has weighed lists every close and each epic's latest shift,
// Deliveries left out.
func TestUnweighedListsEveryChangeOfARigNoSyncWeighed(t *testing.T) {
	sameLines(t, "the changes of a rig no sync weighed", unweighedOn(t, rig(false)), []string{
		"2026-11-10T00:00:00Z | e6 | closed | old close |  |  | ",
		"2026-11-11T00:00:00Z | e4 | shifted | held | continue | 2026-11-12 | ",
		"2026-11-11T00:00:00Z | e8 | shifted | on the new course | continue | 2026-11-12 | ",
		"2026-11-13T09:00:00Z | e1 | shifted | re-aimed the same day |  |  | ",
		"2026-11-14T00:30:00Z | e7 | closed | same day |  |  | ",
		"2026-11-14T05:00:00Z | e5 | shifted | held | close | 2026-11-15 | ",
		"2026-11-15T02:00:00Z | e3 | shifted | re-aimed |  |  | ",
		"2026-11-15T03:00:00Z | e5 | closed | held |  |  | ",
		"2026-11-15T04:00:00Z | c1 | closed | answered |  |  | ",
		"2026-11-15T05:00:00Z | o1 | closed | under a task |  |  | ",
		"2026-11-15T06:00:00Z | p1 | shifted | shifted once parked |  |  | ",
	})
}

// The answer is one read of the store's epics, closed ones included.
func TestUnweighedReadsTheStoresEpicsOnce(t *testing.T) {
	s := rig(true)
	unweighedOn(t, s)
	if fs := s.Finds(); len(fs) != 1 || fs[0].Type != "epic" || !fs[0].Closed {
		t.Errorf("finds = %+v, want one read of the store's epics, closed ones included", fs)
	}
}

// A sitting that marks one of two epics closed the same day and ends before it
// reaches the other leaves that one on the next sync's list.
func TestUnweighedLeavesAnEpicASittingDidNotReach(t *testing.T) {
	s := fake.New()
	s.Put(closed(epicBead("a1", "open", keys(hyp, "epic_weighed_at", "2026-11-14T10:00:00Z")), "2026-11-13T09:00:00Z", "weighed"))
	s.Put(closed(epicBead("b1", "open", hyp), "2026-11-13T10:00:00Z", "not reached"))
	sameLines(t, "after an interrupted sitting", unweighedOn(t, s), []string{
		"2026-11-13T10:00:00Z | b1 | closed | not reached |  |  | ",
	})
}

// A mark takes a close from the day before it off the list, and one on its own
// day lists again, since the sync's read came before the mark.
func TestUnweighedListsAChangeOnItsMarksDayAgain(t *testing.T) {
	today := time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC)
	mark := keys(hyp, "epic_weighed_at", today.Add(18*time.Hour).Format(time.RFC3339))
	s := fake.New()
	s.Put(closed(epicBead("y1", "open", mark), today.Add(-time.Second).Format(time.RFC3339), "the day before"))
	s.Put(closed(epicBead("t1", "open", mark), today.Format(time.RFC3339), "its own day"))
	sameLines(t, "around a mark's day", unweighedOn(t, s), []string{
		"2026-11-15T00:00:00Z | t1 | closed | its own day |  |  | 2026-11-15",
	})
}

// A shift and then a continue after the mark list the shift with the continue
// that followed it. A shift and a continue before the mark list nothing, and
// so does a continue alone after it.
func TestUnweighedListsAShiftALaterRulingFollowed(t *testing.T) {
	mark := keys(hyp, "epic_weighed_at", "2026-11-14T00:00:00Z")
	s := fake.New()
	s.Put(epicBead("r1", "open", keys(ruled(mark, "continue", "2026-11-15T02:00:00Z", "on the new course"),
		"epic_shifted_at", "2026-11-15T01:00:00Z")))
	s.Put(epicBead("r2", "open", keys(ruled(mark, "continue", "2026-11-13T00:00:00Z", "held"),
		"epic_shifted_at", "2026-11-12T00:00:00Z")))
	s.Put(epicBead("r3", "open", ruled(mark, "continue", "2026-11-15T00:00:00Z", "held")))
	sameLines(t, "rulings around a mark", unweighedOn(t, s), []string{
		"2026-11-15T01:00:00Z | r1 | shifted | on the new course | continue | 2026-11-15 | 2026-11-14",
	})
}

// A close or a shift whose time names no day lists whatever the mark says,
// since nothing shows a sync weighed it, and so does every change on an epic
// whose mark names no day.
func TestUnweighedListsAChangeItCannotDate(t *testing.T) {
	s := fake.New()
	s.Put(epicBead("u1", "open", keys(ruled(hyp, "shift", "", "undated"), "epic_weighed_at", "2026-11-14T00:00:00Z")))
	s.Put(closed(epicBead("u2", "open", keys(hyp, "epic_weighed_at", "not a time")), "2026-11-01T00:00:00Z", "an unreadable mark"))
	sameLines(t, "undated", unweighedOn(t, s), []string{
		" | u1 | shifted | undated |  |  | 2026-11-14",
		"2026-11-01T00:00:00Z | u2 | closed | an unreadable mark |  |  | ",
	})
}

// A store that does not answer fails the read, which returns no change, so the
// caller never takes it for a rig where nothing changed.
func TestUnweighedFailsWhenTheStoreDoesNotAnswer(t *testing.T) {
	s := rig(true)
	s.FindErr = &gcbd.ReadError{Reason: "the listing did not answer"}
	if got, err := Unweighed(ledger.New(s)); err == nil || got != nil {
		t.Errorf("a listing that failed = %v, %v; want an error and no change", got, err)
	}
}

// A rig with no epics answers with no change, which is an answer.
func TestUnweighedOfARigWithNoEpicsIsAnAnswer(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "t1", Title: "a task", Status: "closed", IssueType: "task", ClosedAt: "2026-11-15T00:00:00Z"})
	got, err := Unweighed(ledger.New(s))
	if err != nil || len(got) != 0 {
		t.Errorf("a rig with no epics = %v, %v; want no change and no error", got, err)
	}
}

// A template and a bead in the store's ephemeral plane are no epic of the
// rig's, as the store's own listing of epics leaves them out.
func TestUnweighedLeavesOutWhatTheStoresListingOfEpicsHides(t *testing.T) {
	s := fake.New()
	tmpl := closed(epicBead("m1", "open", nil), "2026-11-15T00:00:00Z", "a template")
	tmpl.Template = true
	wisp := closed(epicBead("w1", "open", nil), "2026-11-15T00:00:00Z", "a wisp")
	wisp.Ephemeral = true
	s.Put(tmpl)
	s.Put(wisp)
	s.Put(closed(epicBead("k1", "open", nil), "2026-11-15T00:00:00Z", "kept"))
	sameLines(t, "with a template and a wisp", unweighedOn(t, s), []string{
		"2026-11-15T00:00:00Z | k1 | closed | kept |  |  | ",
	})
}

// A time written with an offset reads by its UTC day, the mark's and the
// change's alike.
func TestUnweighedReadsATimeByItsUTCDay(t *testing.T) {
	mark := keys(hyp, "epic_weighed_at", "2026-11-14T23:30:00-05:00")
	s := fake.New()
	s.Put(closed(epicBead("b1", "open", mark), "2026-11-14T20:00:00Z", "the UTC day before"))
	s.Put(closed(epicBead("s1", "open", mark), "2026-11-15T01:00:00Z", "the mark's UTC day"))
	sameLines(t, "around a mark written with an offset", unweighedOn(t, s), []string{
		"2026-11-15T01:00:00Z | s1 | closed | the mark's UTC day |  |  | 2026-11-15",
	})
}
