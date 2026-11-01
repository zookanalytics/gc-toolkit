package board

import (
	"encoding/json"
	"slices"
	"testing"
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
