package standing

import (
	"errors"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// TestAnOpenPullRequestOnTheRecord: a bead owns an open pull request at either
// value Gas Town's pending record gives one, and at no value that records a
// landing or an end without one.
func TestAnOpenPullRequestOnTheRecord(t *testing.T) {
	for _, v := range []string{"pull_request_pending", "pull_request_head_changed"} {
		if !hasOpenPullRequest(Bead{MergeResult: v}) {
			t.Errorf("merge_result %s owns an open pull request", v)
		}
	}
	for _, v := range []string{"", "mr_merged", "pull_request_closed_unmerged", "pull_request_reconcile_invalid"} {
		if hasOpenPullRequest(Bead{MergeResult: v}) {
			t.Errorf("merge_result %q owns no open pull request", v)
		}
	}
}

// store is a Store over live beads and what holds each. It holds no pull
// request, closed member or live run, and no bead's blocks edges reach a
// person.
type store struct {
	beads []Bead
	holds map[string]waits.Holds
}

func (s store) Rows(ids []string) (map[string]queue.Row, error) {
	out := map[string]queue.Row{}
	for _, b := range s.beads {
		if slices.Contains(ids, b.ID) {
			out[b.ID] = queue.Row{ID: b.ID, Status: b.Status, Assignee: b.Assignee, Labels: b.Labels}
		}
	}
	return out, nil
}

// Ready is the store's ready set, as bd serves one: each open bead waits reads
// as clear.
func (s store) Ready() ([]string, error) {
	var out []string
	for _, b := range s.beads {
		if h, ok := s.holds[b.ID]; ok && h.Status == waits.Clear && b.Status == "open" {
			out = append(out, b.ID)
		}
	}
	return out, nil
}

// Worked names no bead: the store holds no live run.
func (store) Worked([]string) (map[string]bool, error) { return map[string]bool{}, nil }

func (s store) Holds(ids []string) (map[string]waits.Holds, map[string]error, error) {
	holds, failed := map[string]waits.Holds{}, map[string]error{}
	for _, id := range ids {
		if h, ok := s.holds[id]; ok {
			holds[id] = h
		} else {
			failed[id] = errors.New("waits could not answer it")
		}
	}
	return holds, failed, nil
}

func (store) Beads([]string) (map[string]prstatus.Row, error) { return map[string]prstatus.Row{}, nil }

func (store) Anchored([]string, []string) (map[string][]prstatus.Row, error) {
	return map[string][]prstatus.Row{}, nil
}

func (store) Blockers(ids []string) (map[string][]person.Blocker, error) {
	out := map[string][]person.Blocker{}
	for _, id := range ids {
		out[id] = []person.Blocker{}
	}
	return out, nil
}

func (store) PRAnswers([]string) (map[string]pr.Answer, map[string]error) { return nil, nil }

func (s store) Every() []Bead { return s.beads }

func (s store) Find(ids []string) (map[string]Bead, error) {
	out := map[string]Bead{}
	for _, b := range s.beads {
		if slices.Contains(ids, b.ID) {
			out[b.ID] = b
		}
	}
	return out, nil
}

func (store) ClosedBeneath([]string) ([]Bead, error) { return nil, nil }

func (store) LiveRuns() ([]waits.Run, error) { return nil, nil }

// TestAConversationReadsAlikeAskedAloneOrWithEveryBead: a conversation that
// tracks a decision is itself the ask while the decision waits on the work a
// ruling sent, and answers the decision's question while the decision asks,
// whether Read is asked about the conversation alone or about every bead.
func TestAConversationReadsAlikeAskedAloneOrWithEveryBead(t *testing.T) {
	sent := waits.Wait{ID: "tk-w", Type: "blocks", Title: "the work a ruling sent", Status: "open", IssueType: "task"}
	beads := []Bead{
		{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "human",
			Edges: []Edge{{ID: "tk-d", Type: "tracks"}}},
		{ID: "tk-d", Title: "pick one", Status: "open", IssueType: "decision"},
		{ID: "tk-w", Title: "the work a ruling sent", Status: "open", IssueType: "task"},
	}
	for _, c := range []struct {
		name     string
		decision waits.Holds
		rule     Rule
		group    Group
		ask      Ask
		names    []string
	}{
		{name: "the decision waits on the work a ruling sent",
			decision: waits.Holds{ID: "tk-d", Status: waits.Blocked, Waits: []waits.Wait{sent}},
			rule:     RuleAsk, group: GroupWaitingOnYou, ask: AskConversation},
		{name: "the decision asks", decision: waits.Holds{ID: "tk-d", Status: waits.Clear},
			rule: RuleAnswers, names: []string{"tk-d"}},
	} {
		s := store{beads: beads, holds: map[string]waits.Holds{"tk-c": {ID: "tk-c", Status: waits.Clear},
			"tk-d": c.decision, "tk-w": {ID: "tk-w", Status: waits.Clear}}}
		for _, ids := range [][]string{{"tk-c", "tk-d", "tk-w"}, {"tk-c"}} {
			r, err := Read(ids, s)
			if err != nil {
				t.Fatalf("%s, asked about %v: %v", c.name, ids, err)
			}
			a, _ := r.Answer("tk-c")
			var names []string
			for _, n := range a.Names {
				names = append(names, n.ID)
			}
			if a.Rule != c.rule || a.Group != c.group || a.Ask != c.ask || !slices.Equal(names, c.names) {
				t.Errorf("%s, asked about %v: got rule=%q group=%q ask=%q names=%v, want rule=%q group=%q ask=%q names=%v",
					c.name, ids, a.Rule, a.Group, a.Ask, names, c.rule, c.group, c.ask, c.names)
			}
		}
	}
}
