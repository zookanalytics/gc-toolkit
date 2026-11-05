package board

import (
	"encoding/json"
	"slices"
	"testing"
	"time"
)

// TestEachSittingCarriesOneState pins the state a sitting carries on the wire. A
// conversation's status does not decide it: a status of in_progress stays on a
// conversation whose session has ended, and that sitting reads waiting.
func TestEachSittingCarriesOneState(t *testing.T) {
	const (
		alias   = "gc-toolkit/gc-toolkit.tk-conv"
		session = "gc-toolkit__converse-tk-conv"
	)
	state := func(s string) Facts { return Facts{OwnerState: map[string]string{alias: s}} }
	for _, tc := range []struct {
		name    string
		sitting Sitting
		facts   Facts
		want    string
	}{
		{"a live session holds it, by its assignee", Sitting{Status: "in_progress", Assignee: alias}, liveOwners(alias), SittingInSession},
		{"a live session holds it, by its session name", Sitting{Status: "in_progress", Assignee: alias, Session: session}, liveOwners(session), SittingInSession},
		{"a session asleep between turns still holds it", Sitting{Status: "in_progress", Assignee: alias}, state("asleep"), SittingInSession},
		{"open in the operator's queue", Sitting{Status: "open", Assignee: assigneeHuman}, Facts{}, SittingWaiting},
		{"in the queue, its last session still live", Sitting{Status: "open", Assignee: assigneeHuman, Session: session}, liveOwners(session), SittingWaiting},
		{"open with no holder", Sitting{Status: "open", Session: session}, liveOwners(session), SittingWaiting},
		{"its session closed", Sitting{Status: "in_progress", Assignee: alias}, state("closed"), SittingWaiting},
		{"its session archived", Sitting{Status: "in_progress", Assignee: alias}, state("archived"), SittingWaiting},
		{"its session rolled back on a failed create", Sitting{Status: "in_progress", Assignee: alias}, state("failed-create"), SittingWaiting},
		{"its session listed with no state", Sitting{Status: "in_progress", Assignee: alias}, state(""), SittingWaiting},
		{"its session gone from the list", Sitting{Status: "in_progress", Assignee: alias, Session: session}, Facts{}, SittingWaiting},
		{"its last sitting failed to start", Sitting{Status: "in_progress", Assignee: alias, StartFailure: "setup timeout"}, state("failed-create"), SittingStartFailed},
		{"handed back after a failed start", Sitting{Status: "open", Assignee: assigneeHuman, StartFailure: "setup timeout"}, Facts{}, SittingStartFailed},
		{"a failed start outranks a live holder", Sitting{Status: "in_progress", Assignee: alias, StartFailure: "setup timeout"}, liveOwners(alias), SittingStartFailed},
		{"closed", Sitting{Status: "closed", Assignee: assigneeHuman}, Facts{}, SittingClosed},
		{"closed, its session still live", Sitting{Status: "closed", Assignee: alias, Session: session}, liveOwners(alias, session), SittingClosed},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tc.sitting.ID = "tk-conv"
			tc.facts.Sittings = []Sitting{tc.sitting}
			if got := BuildBoard(nil, fixtureNow, false, nil, tc.facts).Sittings[0].State; got != tc.want {
				t.Errorf("state = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestRowRollsUpFromItsSittingsStates: a row reads the states the record carries
// and no reading of its own, so the row and the list cannot disagree. A failed
// start outranks a live sitting, which outranks a waiting one, and a closed
// sitting holds nothing.
func TestRowRollsUpFromItsSittingsStates(t *testing.T) {
	live := func(id string) Sitting {
		return Sitting{ID: id, Subject: "tk-subj", Status: "in_progress", Assignee: sittingAlias(id)}
	}
	queued := func(id string) Sitting {
		return Sitting{ID: id, Subject: "tk-subj", Status: "open", Assignee: assigneeHuman}
	}
	failed := func(id string) Sitting {
		s := queued(id)
		s.StartFailure = "startup timeout"
		return s
	}
	done := func(id string) Sitting {
		s := live(id)
		s.Status = "closed"
		return s
	}
	for _, tc := range []struct {
		name     string
		sittings []Sitting
		want     string
	}{
		{"one in session", []Sitting{live("tk-a")}, SittingInSession},
		{"one waiting", []Sitting{queued("tk-a")}, SittingWaiting},
		{"in session and waiting", []Sitting{queued("tk-a"), live("tk-b")}, SittingInSession},
		{"waiting and start failed", []Sitting{queued("tk-a"), failed("tk-b")}, SittingStartFailed},
		{"in session and start failed", []Sitting{live("tk-a"), failed("tk-b")}, SittingStartFailed},
		{"in session and closed", []Sitting{done("tk-a"), live("tk-b")}, SittingInSession},
	} {
		t.Run(tc.name, func(t *testing.T) {
			anchors := []Anchor{epicSubject("tk-subj")}
			for _, s := range tc.sittings {
				if s.Status != "closed" {
					anchors = append(anchors, conversationAnchor(s.ID, s.Subject, "an ask", s.Assignee))
				}
			}
			b := BuildBoard(anchors, fixtureNow, false, nil, Facts{
				Sittings:   tc.sittings,
				OwnerState: map[string]string{sittingAlias("tk-a"): "active", sittingAlias("tk-b"): "active"},
			})
			if got := mustTile(t, b, "tk-subj").SittingState; got != tc.want {
				t.Errorf("sitting_state = %q, want %q", got, tc.want)
			}
			var states []string
			for _, s := range b.Sittings {
				states = append(states, s.State)
			}
			if !slices.Contains(states, tc.want) {
				t.Errorf("the row reads %q and no sitting on it does: %v", tc.want, states)
			}
		})
	}

	// The record decides, whatever the anchor of the same conversation says.
	// The gather builds both from one task, so this pins that the row has no
	// second reading to fall out of step with.
	b := BuildBoard([]Anchor{epicSubject("tk-subj"), conversationAnchor("tk-a", "tk-subj", "an ask", assigneeHuman)},
		fixtureNow, false, nil, Facts{Sittings: []Sitting{live("tk-a")}, OwnerState: liveOwners(sittingAlias("tk-a")).OwnerState})
	row := mustTile(t, b, "tk-subj")
	if row.SittingState != SittingInSession || row.Owed {
		t.Errorf("the row reads the sitting's state: state=%q owed=%v", row.SittingState, row.Owed)
	}

	// A gather that builds no record, as the supervisor backend's does, reads no
	// conversation in session, whoever it is assigned to.
	b = BuildBoard([]Anchor{epicSubject("tk-subj"), conversationAnchor("tk-a", "tk-subj", "an ask", sittingAlias("tk-a"))},
		fixtureNow, false, nil, liveOwners(sittingAlias("tk-a")))
	if row = mustTile(t, b, "tk-subj"); row.SittingState != SittingWaiting || !row.Owed {
		t.Errorf("with no record the row reads waiting: state=%q owed=%v", row.SittingState, row.Owed)
	}
}

// TestARowOnlyAGateHoldsWaits: the roll-up of no sittings on a held row is
// waiting, because a human gate waits for the operator and no sitting is on it.
func TestARowOnlyAGateHoldsWaits(t *testing.T) {
	row := mustTile(t, BuildBoard([]Anchor{epicSubject("tk-subj"), gateAnchor("tk-g", "an ask", "tk-subj")},
		fixtureNow, false, nil, Facts{}), "tk-subj")
	if !row.Held || row.SittingState != SittingWaiting {
		t.Errorf("held=%v state=%q, want held and waiting", row.Held, row.SittingState)
	}
}

// TestSittingStateAndHeadlineRideTheWire: both are values on the wire, so no
// renderer derives its own, and what they are derived from stays off it, so
// none can. The caller's record is left unstamped.
func TestSittingStateAndHeadlineRideTheWire(t *testing.T) {
	in := []Sitting{{ID: "tk-a", Subject: "tk-subj", SubjectTitle: "the topic", Title: "the ask", Status: "in_progress", Assignee: "tk-a"}}
	b := BuildBoard(nil, fixtureNow, false, nil, Facts{Sittings: in, OwnerState: liveOwners("tk-a").OwnerState})
	if in[0].State != "" || in[0].Headline != "" {
		t.Errorf("the gather's record was written through: %+v", in[0])
	}
	raw, err := json.Marshal(b.Sittings[0])
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]any
	if err := json.Unmarshal(raw, &wire); err != nil {
		t.Fatal(err)
	}
	if wire["state"] != SittingInSession || wire["headline"] != "the topic" {
		t.Errorf("state=%v headline=%v", wire["state"], wire["headline"])
	}
	for _, key := range []string{"status", "assignee", "start_failure"} {
		if _, ok := wire[key]; ok {
			t.Errorf("%s is an input to the state, so it stays off the wire", key)
		}
	}
}

// conversationTwin is the anchor the gather also admits a conversation under
// when it carries the key that kind selects on: the same bead, read as that kind.
func conversationTwin(conv Anchor, kind string) Anchor {
	twin := conv
	twin.Kind, twin.Source = kind, kind
	twin.Subjects, twin.RepliesTo, twin.Assignee = nil, nil, ""
	return twin
}

// TestAConversationReadsTheSameHoweverItWasAdmitted: a key a metadata-keyed kind
// selects on can sit on a conversation, which then reaches the board under both
// kinds, ahead of the conversation on one backend and behind it on the other.
// The whole board reads as it does for a conversation carrying no such key, so
// neither the key nor the order decides what the row or its subject's row says.
func TestAConversationReadsTheSameHoweverItWasAdmitted(t *testing.T) {
	alias := sittingAlias("tk-conv")
	for _, stamp := range []struct{ kind, key, value string }{
		{"human", mdRoutedTo, routedHuman},
		{"parked", mdTakeaway, "what a sitting concluded"},
	} {
		for _, st := range []struct {
			name    string
			sitting Sitting
			facts   Facts
		}{
			{"waiting", Sitting{Status: "open", Assignee: assigneeHuman}, Facts{}},
			{"start failed", Sitting{Status: "open", Assignee: assigneeHuman, StartFailure: "setup timeout"}, Facts{}},
			{"in session", Sitting{Status: "in_progress", Assignee: alias}, liveOwners(alias)},
		} {
			for _, sub := range []struct {
				name    string
				anchors []Anchor
			}{
				{"its subject has no row", nil},
				{"its subject has a row", []Anchor{epicSubject("tk-subj")}},
			} {
				t.Run(stamp.kind+"/"+st.name+"/"+sub.name, func(t *testing.T) {
					st.sitting.ID, st.sitting.Subject = "tk-conv", "tk-subj"
					st.facts.Sittings = []Sitting{st.sitting}
					read := func(admitted ...Anchor) string {
						t.Helper()
						raw, err := json.Marshal(BuildBoard(append(admitted, sub.anchors...), fixtureNow, false, nil, st.facts))
						if err != nil {
							t.Fatal(err)
						}
						return string(raw)
					}
					plain := conversationAnchor("tk-conv", "tk-subj", "talk the plan over", st.sitting.Assignee)
					carrying := plain
					carrying.Metadata = map[string]string{stamp.key: stamp.value}
					twin := conversationTwin(carrying, stamp.kind)

					want := read(plain)
					for _, tc := range []struct {
						name     string
						admitted []Anchor
					}{
						{"the key alone", []Anchor{carrying}},
						{"the other kind first", []Anchor{twin, carrying}},
						{"the other kind second", []Anchor{carrying, twin}},
					} {
						if got := read(tc.admitted...); got != want {
							t.Errorf("%s reads differently from a conversation with no such key:\n got %s\nwant %s", tc.name, got, want)
						}
					}
				})
			}
		}
	}
}

// TestRowAndListAgreeOnAConversationAdmittedTwice pins what the row prints beside
// what the list prints, for a conversation carrying `gc.routed_to=human` and
// gathered the way the beads backend gathers it, the routed kind first. Each
// state reads the same in both places, on the conversation's own row and on the
// row of a subject it folds onto.
func TestRowAndListAgreeOnAConversationAdmittedTwice(t *testing.T) {
	alias := sittingAlias("tk-conv")
	for _, tc := range []struct {
		name    string
		sitting Sitting
		facts   Facts
		want    string
		reason  string
		owed    bool
		section string
		needs   string
	}{
		{
			name:    "in session",
			sitting: Sitting{Status: "in_progress", Assignee: alias},
			facts:   liveOwners(alias),
			want:    SittingInSession, section: SectionActive,
			needs: "in conversation",
		},
		{
			name:    "waiting",
			sitting: Sitting{Status: "open", Assignee: assigneeHuman},
			want:    SittingWaiting, owed: true, section: SectionGate,
			needs: "talk the plan over",
		},
		{
			name:    "start failed",
			sitting: Sitting{Status: "open", Assignee: assigneeHuman, StartFailure: "setup timeout"},
			want:    SittingStartFailed, reason: "setup timeout", owed: true, section: SectionGate,
			needs: "start failed (setup timeout): talk the plan over",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tc.sitting.ID, tc.sitting.Subject = "tk-conv", "tk-subj"
			tc.facts.Sittings = []Sitting{tc.sitting}
			conv := conversationAnchor("tk-conv", "tk-subj", "talk the plan over", tc.sitting.Assignee)
			conv.Metadata = map[string]string{mdRoutedTo: routedHuman}
			twin := conversationTwin(conv, "human")

			b := BuildBoard([]Anchor{twin, conv}, fixtureNow, false, nil, tc.facts)
			if got := b.Sittings[0].State; got != tc.want {
				t.Errorf("the list reads %q, want %q", got, tc.want)
			}
			row := mustTile(t, b, "tk-conv")
			if row.SittingState != tc.want || row.SittingStartFailure != tc.reason || !row.Held || row.Kind != KindConversation {
				t.Errorf("its own row: state=%q reason=%q held=%v kind=%q, want %q reason %q, held", row.SittingState, row.SittingStartFailure, row.Held, row.Kind, tc.want, tc.reason)
			}
			if row.Owed != tc.owed || row.Section != tc.section || row.Needs != tc.needs {
				t.Errorf("its own row: owed=%v section=%q needs=%q, want owed=%v section=%q needs=%q", row.Owed, row.Section, row.Needs, tc.owed, tc.section, tc.needs)
			}

			b = BuildBoard([]Anchor{twin, conv, epicSubject("tk-subj")}, fixtureNow, false, nil, tc.facts)
			if got := b.Sittings[0].State; got != tc.want {
				t.Errorf("beside a subject's row the list reads %q, want %q", got, tc.want)
			}
			subj := mustTile(t, b, "tk-subj")
			if subj.SittingState != tc.want || subj.SittingStartFailure != tc.reason || !subj.Held || subj.Owed != tc.owed || subj.Needs != tc.needs {
				t.Errorf("the subject's row: state=%q reason=%q held=%v owed=%v needs=%q, want %q reason %q owed=%v needs=%q", subj.SittingState, subj.SittingStartFailure, subj.Held, subj.Owed, subj.Needs, tc.want, tc.reason, tc.owed, tc.needs)
			}
			if _, doubled := tileByID(b, "tk-conv"); doubled {
				t.Error("the conversation keeps a row beside its subject's")
			}
		})
	}

	// A closed conversation is a sitting and no conversation anchor, so the routed
	// kind alone admits it. The list reads closed, and its row is a closed row,
	// which holds nothing and marks nothing.
	t.Run("closed", func(t *testing.T) {
		twin := Anchor{ID: "tk-conv", Kind: "human", Source: "human", Title: "talk the plan over",
			ClosedAt: fixtureNow.Add(-time.Hour), Metadata: map[string]string{mdRoutedTo: routedHuman}}
		b := BuildBoard([]Anchor{twin}, fixtureNow, false, nil, Facts{
			Sittings: []Sitting{{ID: "tk-conv", Subject: "tk-subj", Status: "closed", Assignee: assigneeHuman, ClosedAt: fixtureNow.Add(-time.Hour)}},
		})
		if got := b.Sittings[0].State; got != SittingClosed {
			t.Errorf("the list reads %q, want %q", got, SittingClosed)
		}
		row := mustTile(t, b, "tk-conv")
		if row.ClosedAt.IsZero() || row.SittingState != "" || row.Held || row.Owed {
			t.Errorf("a closed row holds and marks nothing: closed_at=%v state=%q held=%v owed=%v", row.ClosedAt, row.SittingState, row.Held, row.Owed)
		}
	})
}

// TestDropConversationTwinsLeavesOtherBeadsAdmittedTwice: only a conversation is
// settled ahead of the dedup. A bead admitted under two other kinds keeps both
// anchors, for the dedup to reconcile by band, and the caller's slice is left
// as it was.
func TestDropConversationTwinsLeavesOtherBeadsAdmittedTwice(t *testing.T) {
	routed := Anchor{ID: "tk-both", Kind: "human", Source: "human"}
	parked := Anchor{ID: "tk-both", Kind: "parked", Source: "parked"}
	conv := conversationAnchor("tk-conv", "tk-subj", "an ask", assigneeHuman)
	in := []Anchor{conversationTwin(conv, "human"), routed, conv, parked}

	var got []string
	for _, a := range dropConversationTwins(in) {
		got = append(got, a.ID+":"+a.Source)
	}
	want := []string{"tk-both:human", "tk-conv:conversation", "tk-both:parked"}
	if !slices.Equal(got, want) {
		t.Errorf("anchors = %v, want %v", got, want)
	}
	if in[0].Source != "human" || in[3].ID != "tk-both" {
		t.Errorf("the caller's anchors were written through: %+v", in)
	}
}
