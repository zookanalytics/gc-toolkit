package standing

import (
	"errors"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus/fixture"
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

// pullStore is a store that holds pull requests: prstatus's reads answer from a
// fixture store over the same beads, and the evaluator's answer for each pull
// request on Gas Town's pending record comes from answers.
type pullStore struct {
	store
	prs     *fixture.Store
	answers map[string]pr.Answer
}

func (s pullStore) Beads(ids []string) (map[string]prstatus.Row, error) { return s.prs.Beads(ids) }

func (s pullStore) Anchored(ids, statuses []string) (map[string][]prstatus.Row, error) {
	return s.prs.Anchored(ids, statuses)
}

func (s pullStore) Blockers(ids []string) (map[string][]person.Blocker, error) {
	return s.prs.Blockers(ids)
}

func (s pullStore) PRAnswers(ids []string) (map[string]pr.Answer, map[string]error) {
	out, failed := map[string]pr.Answer{}, map[string]error{}
	for _, id := range ids {
		if a, ok := s.answers[id]; ok {
			out[id] = a
		} else {
			failed[id] = errors.New("no answer")
		}
	}
	return out, failed
}

// pullStoreOf is a pullStore over beads, each held by its own open `blocks`
// edges as waits reads them, and pull request tk-pr's answer.
func pullStoreOf(beads []Bead, answer pr.Answer) pullStore {
	byID := map[string]Bead{}
	for _, b := range beads {
		byID[b.ID] = b
	}
	var rows []fixture.Bead
	holds := map[string]waits.Holds{}
	for _, b := range beads {
		row := fixture.Bead{ID: b.ID, Title: b.Title, Status: b.Status, IssueType: b.IssueType, AwaitType: b.AwaitType,
			Assignee: b.Assignee, WaitsOn: edgesOf(b, "blocks"), Tracks: edgesOf(b, "tracks")}
		if b.MergeResult != "" {
			row.Metadata = map[string]string{"merge_result": b.MergeResult}
		}
		rows = append(rows, row)
		h := waits.Holds{ID: b.ID, Status: waits.Clear}
		for _, w := range edgesOf(b, "blocks") {
			far := byID[w]
			h.Status = waits.Blocked
			h.Waits = append(h.Waits, waits.Wait{ID: far.ID, Type: "blocks", Title: far.Title, Status: far.Status,
				IssueType: far.IssueType, AwaitType: far.AwaitType})
		}
		holds[b.ID] = h
	}
	return pullStore{store: store{beads: beads, holds: holds}, prs: fixture.NewStore(rows),
		answers: map[string]pr.Answer{"tk-pr": answer}}
}

// TestAPullRequestBeneathAnAskReadsAlikeAskedAloneOrWithEveryBead: a pull
// request whose needs-attention rests only on the human gates and the beads a
// person owes that hold it is no ask while one of them stands in an ask, and
// reads as waiting on them, whether Read is asked about the pull request alone,
// as `gctk bead stands` asks, or about every bead, as the helm board asks. One
// with a reason of its own beside them is an ask, and so is one whose holders
// stand in no ask, so it stays a person's move of its own.
func TestAPullRequestBeneathAnAskReadsAlikeAskedAloneOrWithEveryBead(t *testing.T) {
	sitting := "gc-toolkit/gc-toolkit.tk-c"
	blocks := func(ids ...string) []Edge {
		var out []Edge
		for _, id := range ids {
			out = append(out, Edge{ID: id, Type: "blocks"})
		}
		return out
	}
	anchor := func(waitsOn ...string) Bead {
		return Bead{ID: "tk-pr", Title: "the change", Status: "blocked", IssueType: "task", Assignee: "gc-toolkit/refinery",
			MergeResult: "pull_request_pending", PRNumber: "7", Edges: blocks(waitsOn...)}
	}
	q := Bead{ID: "tk-q", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"}
	d := Bead{ID: "tk-d", Title: "keep the old flag?", Status: "open", IssueType: "decision"}
	talk := func(edges ...Edge) Bead {
		return Bead{ID: "tk-c", Title: "talk it over", Status: "in_progress", IssueType: "task", Assignee: sitting, Edges: edges}
	}
	wait := func(id string) pr.Condition { return pr.Condition{Kind: pr.KindWait, ID: id} }
	for _, c := range []struct {
		name    string
		beads   []Bead
		answer  pr.Answer
		rule    Rule
		ask     Ask
		names   []string
		beneath []string
		stuckOn string
		why     string
	}{
		{name: "a question alone holds it",
			beads:  []Bead{anchor("tk-q"), q},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-q")}},
			rule:   RuleOwnWait, names: []string{"tk-q"}, beneath: []string{"tk-q"}, stuckOn: "tk-q", why: "own-wait"},
		{name: "a question and a hold set by hand hold it",
			beads:  []Bead{anchor("tk-q"), q},
			answer: pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindHold}, wait("tk-q")}},
			rule:   RuleAsk, ask: AskPullRequest, beneath: []string{"tk-q"}, stuckOn: "tk-pr", why: "pull-request"},
		{name: "a conversation a sitting holds holds it",
			beads:  []Bead{anchor("tk-c"), talk(Edge{ID: "tk-pr", Type: "tracks"})},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-c")}},
			rule:   RuleOwnWait, names: []string{"tk-c"}, beneath: []string{"tk-c"}, stuckOn: "tk-c", why: "own-wait"},
		{name: "a question and the conversation that answers it hold it",
			beads:  []Bead{anchor("tk-q", "tk-c"), q, talk(Edge{ID: "tk-pr", Type: "tracks"}, Edge{ID: "tk-q", Type: "replies-to"})},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-q"), wait("tk-c")}},
			rule:   RuleOwnWait, names: []string{"tk-q"}, beneath: []string{"tk-q"}, stuckOn: "tk-q", why: "own-wait"},
		{name: "the conversation that answers a question holds it, and the question does not",
			beads:  []Bead{anchor("tk-c"), q, talk(Edge{ID: "tk-pr", Type: "tracks"}, Edge{ID: "tk-q", Type: "replies-to"})},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-c")}},
			rule:   RuleOwnWait, names: []string{"tk-c"}, beneath: []string{"tk-q"}, stuckOn: "tk-c", why: "own-wait"},
		{name: "a question holds the work it waits on, further along",
			beads: []Bead{anchor("tk-fix"), q,
				{ID: "tk-fix", Title: "fix the branch", Status: "open", IssueType: "task", Edges: blocks("tk-q")}},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-fix")}},
			rule:   RuleFurtherAlong, names: []string{"tk-q"}, beneath: []string{"tk-q"}, stuckOn: "tk-q", why: "further-along"},
		{name: "a conversation that answers a decision holds it",
			beads:  []Bead{anchor("tk-c"), d, talk(Edge{ID: "tk-d", Type: "tracks"})},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-c")}},
			rule:   RuleOwnWait, names: []string{"tk-c"}, beneath: []string{"tk-d"}, stuckOn: "tk-c", why: "own-wait"},
		{name: "work in your queue held for the Product Owner, which asks nothing, holds it",
			beads: []Bead{anchor("tk-w"),
				{ID: "tk-w", Title: "sign the form", Status: "open", IssueType: "task", Assignee: "human", Labels: []string{"hold:mayor"}}},
			answer: pr.Answer{Conditions: []pr.Condition{wait("tk-w")}},
			rule:   RuleAsk, ask: AskPullRequest, stuckOn: "tk-pr", why: "pull-request"},
	} {
		s := pullStoreOf(c.beads, c.answer)
		var every []string
		for _, b := range c.beads {
			every = append(every, b.ID)
		}
		for _, ids := range [][]string{every, {"tk-pr"}} {
			r, err := Read(ids, s)
			if err != nil {
				t.Fatalf("%s, asked about %v: %v", c.name, ids, err)
			}
			a, _ := r.Answer("tk-pr")
			var names []string
			for _, n := range a.Names {
				names = append(names, n.ID)
			}
			if a.Rule != c.rule || a.Group != GroupWaitingOnYou || a.Ask != c.ask || !slices.Equal(names, c.names) {
				t.Errorf("%s, asked about %v: got rule=%q group=%q ask=%q names=%v, want rule=%q group=%q ask=%q names=%v",
					c.name, ids, a.Rule, a.Group, a.Ask, names, c.rule, GroupWaitingOnYou, c.ask, c.names)
			}
			if got := r.Beneath("tk-pr"); !slices.Equal(got, c.beneath) {
				t.Errorf("%s, asked about %v: tk-pr stands beneath %v, want %v", c.name, ids, got, c.beneath)
			}
			if adv, _ := r.Advance("tk-pr"); adv.Advancing || adv.On != c.stuckOn || adv.Why != c.why {
				t.Errorf("%s, asked about %v: tk-pr's advance = %+v, want stuck on %s, %s", c.name, ids, adv, c.stuckOn, c.why)
			}
		}
	}
}

// TestAFrontierBehindAPullRequestBeneathAnAsk: work that waits on a pull request
// a question alone holds reads that pull request as stuck on the question,
// whether Read is asked about the work alone, as bead-context.sh asks for its
// frontier, or about every bead.
func TestAFrontierBehindAPullRequestBeneathAnAsk(t *testing.T) {
	beads := []Bead{
		{ID: "tk-w", Title: "the next change", Status: "open", IssueType: "task", Edges: []Edge{{ID: "tk-pr", Type: "blocks"}}},
		{ID: "tk-pr", Title: "the change", Status: "blocked", IssueType: "task", Assignee: "gc-toolkit/refinery",
			MergeResult: "pull_request_pending", PRNumber: "7", Edges: []Edge{{ID: "tk-q", Type: "blocks"}}},
		{ID: "tk-q", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"},
	}
	s := pullStoreOf(beads, pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindWait, ID: "tk-q"}}})
	for _, ids := range [][]string{{"tk-w", "tk-pr", "tk-q"}, {"tk-w"}} {
		r, err := Read(ids, s)
		if err != nil {
			t.Fatalf("asked about %v: %v", ids, err)
		}
		f, ok := r.Frontier("tk-w")
		want := Waited{ID: "tk-pr", Advance: Advance{On: "tk-q", Why: string(RuleOwnWait)}}
		if !ok || f.Verdict != VerdictStuck || !slices.Equal(f.Waits, []Waited{want}) {
			t.Errorf("asked about %v: tk-w's frontier = %+v, want stuck with %+v", ids, f, want)
		}
	}
}
