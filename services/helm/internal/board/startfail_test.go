package board

import (
	"fmt"
	"strings"
	"testing"
)

// failedConversation is a conversation whose sitting failed to start, as the
// gather leaves it: still held under the alias of the sitting that never
// started.
func failedConversation(id, subject, ask string) Anchor {
	return conversationAnchor(id, subject, ask, sittingAlias(id))
}

// failedStart is the facts that failed start leaves: Gas City lists the
// session under the sitting's alias as failed-create, and the conversation's
// record carries the reason Gas City recorded.
func failedStart(id, subject, reason string) Facts {
	return Facts{
		OwnerState: map[string]string{sittingAlias(id): "failed-create"},
		Sittings:   []Sitting{{ID: id, Subject: subject, Status: "in_progress", StartFailure: reason}},
	}
}

// TestStartFailedConversationReadsStartFailedWithItsReason: the held row reads
// the failure, not "waiting" (which is what the dead binding alone would say).
// It is owed, at least ELEVATED, and NEEDS leads with the reason ahead of the
// ask.
func TestStartFailedConversationReadsStartFailedWithItsReason(t *testing.T) {
	anchors := []Anchor{
		failedConversation("tk-conv", "tk-subj", "talk the plan over"),
		epicSubject("tk-subj"),
	}
	facts := failedStart("tk-conv", "tk-subj", "setup timeout")
	b := BuildBoard(anchors, fixtureNow, false, nil, facts)
	if got := b.Sittings[0].State; got != SittingStartFailed {
		t.Errorf("the sitting reads start failed too: %q", got)
	}
	subj := mustTile(t, b, "tk-subj")
	if subj.SittingState != SittingStartFailed || subj.SittingStartFailure != "setup timeout" {
		t.Errorf("state=%q reason=%q, want start-failed with the reason", subj.SittingState, subj.SittingStartFailure)
	}
	if got, want := subj.Needs, "start failed (setup timeout): talk the plan over"; got != want {
		t.Errorf("NEEDS = %q, want %q", got, want)
	}
	if !subj.Owed || subj.Section != SectionGate {
		t.Errorf("a failed start is the operator's move: owed=%v section=%q", subj.Owed, subj.Section)
	}
	if subj.Severity != SevElevated {
		t.Errorf("a NORMAL row whose sitting failed to start bands ELEVATED: %s", subj.Severity)
	}
	if subj.RankScore != rankScore(SevElevated, subj.Weight, subj.StaleDays, 0) {
		t.Errorf("rank_score follows the lifted band: %d", subj.RankScore)
	}
	if indexHuman(anchors, withSittings(anchors, facts)).inSessionOn("tk-subj") {
		t.Error("a binding to a sitting that never started is not a sitting in session")
	}
}

// TestStartFailedOwnRowStaysInTheQueue: a conversation whose subject has no row
// keeps a row of its own, which waits for the operator. A failed start marks
// that row, keeps it owed, and lifts it to ELEVATED.
func TestStartFailedOwnRowStaysInTheQueue(t *testing.T) {
	control := mustTile(t, BuildBoard([]Anchor{conversationAnchor("tk-conv", "tk-plain", "talk the plan over", assigneeHuman)},
		fixtureNow, false, nil, Facts{}), "tk-conv")
	if control.SittingState != SittingWaiting || !control.Owed {
		t.Fatalf("fixture: a conversation's own row waits for the operator; got state=%q owed=%v", control.SittingState, control.Owed)
	}

	row := mustTile(t, BuildBoard([]Anchor{failedConversation("tk-conv", "tk-plain", "talk the plan over")},
		fixtureNow, false, nil, failedStart("tk-conv", "tk-plain", "startup timeout")), "tk-conv")
	if row.SittingState != SittingStartFailed || row.SittingStartFailure != "startup timeout" {
		t.Errorf("the conversation's own row reads start failed: state=%q reason=%q", row.SittingState, row.SittingStartFailure)
	}
	if !row.Owed || row.Severity.rank() < SevElevated.rank() || row.Section != SectionGate {
		t.Errorf("a failed start keeps the row in the queue: owed=%v %s section=%q", row.Owed, row.Severity, row.Section)
	}
	if !strings.HasPrefix(row.Needs, "start failed (startup timeout): ") {
		t.Errorf("NEEDS leads with the failure: %q", row.Needs)
	}
}

// TestStartFailedLeadsTheQueue: by age a failed start sorts at the tail, below
// the head the picker offers. It leads the queue instead, and the cap keeps it.
func TestStartFailedLeadsTheQueue(t *testing.T) {
	build := func(conv Anchor, facts Facts) []Tile {
		conv.UpdatedAt = fixtureNow // the conversation was filed just now
		anchors := []Anchor{conv, epicSubject("tk-subj")}
		for i := 0; i < 50; i++ {
			anchors = append(anchors, Anchor{
				ID: fmt.Sprintf("tk-old%02d", i), Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
				UpdatedAt: daysAgo(30 + i), Metadata: map[string]string{"gc.routed_to": "human"},
			})
		}
		return OperatorQueue(BuildBoard(anchors, fixtureNow, false, nil, facts).Tiles)
	}

	queue := build(failedConversation("tk-conv", "tk-subj", "talk the plan over"), failedStart("tk-conv", "tk-subj", "startup timeout"))
	if queue[0].ID != "tk-subj" {
		t.Errorf("the failed start leads the queue: got %s first", queue[0].ID)
	}
	if capped := CapQueue(queue, 36); capped[0].ID != "tk-subj" {
		t.Errorf("the cap keeps the head: got %s first", capped[0].ID)
	}

	// The same row waiting sorts by age, behind every row owed longer.
	waiting := build(conversationAnchor("tk-conv", "tk-subj", "talk the plan over", assigneeHuman), Facts{})
	if last := waiting[len(waiting)-1]; last.ID != "tk-subj" {
		t.Errorf("control: a conversation filed just now sorts last, got %s last", last.ID)
	}
}

// TestStartFailedRowStillOffersAccept: a sitting never withholds Accept, so a
// failed start does not either. The recommendation row reads start failed and
// offers Accept, while the failed start's binding stands and once the
// conversation is handed back to the operator's queue.
func TestStartFailedRowStillOffersAccept(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-dispose-pr?")
	for _, tc := range []struct{ name, assignee, status string }{
		{"bound to the sitting that never started", sittingAlias("tk-conv"), "in_progress"},
		{"handed back to the operator's queue", assigneeHuman, "open"},
	} {
		anchors := append([]Anchor{
			recommendationSubject("tk-subj", "mol-dispose-pr", rec),
			conversationAnchor("tk-conv", "tk-subj", rec.Title, tc.assignee, "tk-rec"),
		}, gatesFor("tk-subj", rec)...)
		facts := failedStart("tk-conv", "tk-subj", "startup timeout")
		facts.Sittings[0].Status = tc.status
		row := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, facts), "tk-subj")
		if row.SittingState != SittingStartFailed || !row.Acceptable {
			t.Errorf("%s: state=%q acceptable=%v, want start-failed and Accept", tc.name, row.SittingState, row.Acceptable)
		}
	}
}

// TestStartFailureOutranksALiveSitting: two conversations on one subject are two
// conversations. A live sitting in one does not hide that the other's never
// started.
func TestStartFailureOutranksALiveSitting(t *testing.T) {
	facts := failedStart("tk-conv2", "tk-subj", "never started")
	facts.OwnerState[sittingAlias("tk-conv1")] = "active"
	anchors := []Anchor{
		epicSubject("tk-subj"),
		conversationAnchor("tk-conv1", "tk-subj", "talk the plan over", sittingAlias("tk-conv1")),
		failedConversation("tk-conv2", "tk-subj", "settle the rework"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, withSittings(anchors, facts))
	if subj := mustTile(t, b, "tk-subj"); subj.SittingState != SittingStartFailed || subj.SittingStartFailure != "never started" {
		t.Errorf("state=%q reason=%q, want the failure", subj.SittingState, subj.SittingStartFailure)
	}
	states := map[string]string{}
	for _, s := range b.Sittings {
		states[s.ID] = s.State
	}
	if states["tk-conv1"] != SittingInSession || states["tk-conv2"] != SittingStartFailed {
		t.Errorf("each sitting keeps its own state under the row's roll-up: %v", states)
	}
}

// TestClosedSubjectIsNeverMarked: a closed anchor is never owed, so its DONE row
// is not marked. The fold leaves the open conversation on a row of its own, and
// that row carries the failure.
func TestClosedSubjectIsNeverMarked(t *testing.T) {
	closed := epicSubject("tk-subj")
	closed.ClosedAt = daysAgo(1)
	b := BuildBoard([]Anchor{failedConversation("tk-conv", "tk-subj", "talk the plan over"), closed}, fixtureNow, false, nil,
		failedStart("tk-conv", "tk-subj", "startup timeout"))
	if subj := mustTile(t, b, "tk-subj"); subj.SittingState == SittingStartFailed || subj.Owed {
		t.Errorf("a DONE row is never marked or owed: state=%q owed=%v", subj.SittingState, subj.Owed)
	}
	if own := mustTile(t, b, "tk-conv"); own.SittingState != SittingStartFailed || !own.Owed {
		t.Errorf("the conversation's own row carries the failure: state=%q owed=%v", own.SittingState, own.Owed)
	}
}

// TestStartFailedRowClustersOnWhatItReads: rows sharing a section and a needs
// sentence fold into one line, and the mark rewrites the failed row's section
// and needs. So the row clusters on what it reads after the mark, and stands on
// a line of its own rather than behind a sentence it no longer carries, while
// the rows it used to share that sentence with still fold together.
func TestStartFailedRowClustersOnWhatItReads(t *testing.T) {
	ids := []string{"tk-a", "tk-b", "tk-c", "tk-d"}
	facts := failedStart("tk-conv-a", "tk-a", "startup timeout")
	var anchors []Anchor
	for _, id := range ids {
		conv := conversationAnchor("tk-conv-"+id[3:], id, "talk the plan over", assigneeHuman)
		if id == "tk-a" {
			conv = failedConversation("tk-conv-a", id, "talk the plan over")
		}
		anchors = append(anchors, epicSubject(id), conv)
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, facts)

	failed := mustTile(t, b, "tk-a")
	if failed.SittingState != SittingStartFailed || failed.ClusterKey != "" {
		t.Errorf("the failed start stands on its own line: state=%q cluster_key=%q needs=%q",
			failed.SittingState, failed.ClusterKey, failed.Needs)
	}
	for _, id := range ids[1:] {
		if got := mustTile(t, b, id); got.ClusterKey == "" || got.ClusterKey != got.Needs {
			t.Errorf("%s folds with the rows sharing its needs: cluster_key=%q needs=%q", id, got.ClusterKey, got.Needs)
		}
	}
}
