package review_test

import (
	"errors"
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// Triage's answer (specs/tk-1tfzr71.161/design.md, section 3, "The cheap
// answer"): triage answers a person's post that asks for no change to the
// branch and no person's decision, its output carries the ruling, and
// rule-and-repair does no work for it. Each case starts from the run of
// newWorld, whose bead names its PR.

const prURL = "https://github.com/acme/widgets/pull/7"

// postAsk puts an open ask on the PR's bead for a person's post on the PR, as
// the take files one: of the kind named, at the URL fragment frag, filed at
// the instant given. The bead names the PR's URL.
func (w *world) postAsk(id, kind, frag, filed string) {
	pr, _ := w.store.Row(prBead)
	pr.Metadata["pr_url"] = prURL
	pr.Edges = append(pr.Edges, gcbd.Edge{ID: id, Type: gcbd.EdgeBlocks})
	w.store.Put(pr)
	w.store.Put(bead{ID: id, Status: "open", IssueType: "task", CreatedAt: filed,
		Description: fmt.Sprintf("%s by operator on PR #7: %s#%s", kind, prURL, frag),
		Metadata:    map[string]string{"branch": branch}})
}

// answers is triage's output at h1 in iteration n, with the checks given,
// ruling each ask in rs.
func answers(n int, rs []review.Ruling, checks ...string) review.Triage {
	t := triage(n, h1, checks...)
	t.Rulings = rs
	return t
}

func answer(ask, reason string) review.Ruling {
	return review.Ruling{Ask: ask, Ruling: review.RulingAnswered, Reason: reason}
}

func wordless(ask, reason string) review.Ruling {
	r := answer(ask, reason)
	r.Wordless = true
	return r
}

// Triage's answer of a person's post stands, with words or wordless, and the
// output prints it as the store keeps it.
func TestTriageAnswersAPost(t *testing.T) {
	w := newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.postAsk("tk-lgtm", "Approval message", "pullrequestreview-200", "2026-11-12T03:00:00Z")
	st := w.step(1, "triage")
	var got review.Triage
	if err := w.check(st, answers(1, []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head."),
		wordless("tk-lgtm", "An approval that asks for nothing.")}), &got); err != nil {
		t.Fatal(err)
	}
	want := []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head."),
		wordless("tk-lgtm", "An approval that asks for nothing.")}
	if !reflect.DeepEqual(got.Rulings, want) {
		t.Fatalf("the printed output carries the rulings %+v; want %+v", got.Rulings, want)
	}
}

// Triage answers only a person's post, and leaves every other ruling to
// rule-and-repair: a ruling of a lane's finding, of an ask that carries no
// person's post, of an ask the round cannot take, an ask ruled twice, a
// ruling other than answered, an answer with no reason, and one that names a
// commit, a gate or a question it settles are refused. With no reader of the
// posts an ask names, nothing is checked.
func TestTriageAnswersOnlyAPost(t *testing.T) {
	setup := func() (*world, string) {
		w := newWorld(t)
		w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
		w.ask("tk-change", "")
		w.store.Put(bead{ID: "tk-other", Status: "open", IssueType: "task"})
		w.postAsk("tk-held", "Inline comment", "discussion_r260", "2026-11-12T03:00:00Z")
		held, _ := w.store.Row("tk-held")
		held.Edges = append(held.Edges, gcbd.Edge{ID: "tk-other", Type: gcbd.EdgeBlocks})
		w.store.Put(held)
		w.store.List("tk-held", "tk-other")
		w.store.Mark("tk-held")
		return w, w.step(1, "triage")
	}
	q := answer("tk-q", "The suite took 7 minutes at this head.")
	with := func(change func(*review.Ruling)) review.Ruling {
		r := q
		change(&r)
		return r
	}
	for _, c := range []struct {
		name string
		rs   []review.Ruling
		why  string
	}{
		{"a lane's finding", []review.Ruling{finding("correctness", "F1", review.RulingAnswered)}, "triage rules no lane's finding"},
		{"an ask and a finding at once", []review.Ruling{with(func(r *review.Ruling) { r.Check, r.Finding = "correctness", "F1" })},
			"names the ask tk-q and a lane's finding at once"},
		{"an ask that carries no post", []review.Ruling{answer("tk-change", "nothing to change")}, "carries no person's post"},
		{"an ask something holds", []review.Ruling{answer("tk-held", "r")}, "not an ask the round can take"},
		{"an ask not on the bead", []review.Ruling{answer("tk-nowhere", "r")}, "not an ask the round can take"},
		{"an ask ruled twice", []review.Ruling{q, q}, "ruled twice"},
		{"a decline", []review.Ruling{with(func(r *review.Ruling) { r.Ruling = review.RulingDeclined })}, `ruled "declined"`},
		{"a must-fix", []review.Ruling{with(func(r *review.Ruling) { r.Ruling, r.Commit = review.RulingMustFix, fix })}, `ruled "must-fix"`},
		{"a question", []review.Ruling{with(func(r *review.Ruling) { r.Ruling, r.Gate = review.RulingQuestion, "tk-g" })}, `ruled "question"`},
		{"no reason", []review.Ruling{with(func(r *review.Ruling) { r.Reason = " " })}, "answered with no reason"},
		{"a commit", []review.Ruling{with(func(r *review.Ruling) { r.Commit = fix })}, "only rule-and-repair names"},
		{"a question it settles", []review.Ruling{with(func(r *review.Ruling) { r.Settles = "tk-g" })}, "only rule-and-repair names"},
	} {
		t.Run(c.name, func(t *testing.T) {
			w, st := setup()
			mustRefuse(t, w.check(st, answers(1, c.rs), nil), c.why)
		})
	}

	w, st := setup()
	_, err := review.Output(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, answers(1, []review.Ruling{q}))})
	var refused *review.Refused
	if err == nil || errors.As(err, &refused) {
		t.Fatalf("triage's answers with no reader of posts return %v; want an error, not a refusal", err)
	}
	if _, err := review.Output(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, triage(1, h1))}); err != nil {
		t.Fatalf("a triage that answers nothing needs no reader of posts: %v", err)
	}
}

// questionAt puts a question a review run put to a person on the bead, a human
// gate under a question's key that the bead waits on, filed at the instant
// given.
func (w *world) questionAt(id, status, filed string) {
	w.question(id, review.QuestionKey+"cap", status, true)
	g, _ := w.store.Row(id)
	g.CreatedAt = filed
	w.store.Put(g)
}

// While a question a review run put to a person is open on the bead, triage
// answers no post, since a post may settle it, and it never answers an ask
// filed before such a question was put, which may be the question's own:
// rule-and-repair rules those by the person's answer. A post filed after a
// question closed is triage's to answer.
func TestTriageLeavesAQuestionsPostsToRuleAndRepair(t *testing.T) {
	q := []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head.")}

	w := newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T05:00:00Z")
	w.questionAt("tk-g", "open", "2026-11-12T04:00:00Z")
	mustRefuse(t, w.check(w.step(1, "triage"), answers(1, q), nil), "the question at tk-g is open on "+prBead)

	w = newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.questionAt("tk-g", "closed", "2026-11-12T04:00:00Z")
	mustRefuse(t, w.check(w.step(1, "triage"), answers(1, q), nil), "was filed before the question at tk-g")

	w = newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T05:00:00Z")
	w.questionAt("tk-g", "closed", "2026-11-12T04:00:00Z")
	if err := w.check(w.step(1, "triage"), answers(1, q), nil); err != nil {
		t.Fatalf("a post filed after the question closed is refused: %v", err)
	}
}

// Rule-and-repair rules every ask triage left it and none triage answered,
// whose answer the round has posted.
func TestRuleAndRepairRulesWhatTriageLeft(t *testing.T) {
	w := newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.postAsk("tk-change", "Inline comment", "discussion_r260", "2026-11-12T03:00:00Z")
	w.output(answers(1, []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head.")}))
	st := w.step(1, "rule-and-repair")
	change := review.Ruling{Ask: "tk-change", Ruling: review.RulingDeclined, Reason: "a nit, answered and not fixed"}
	if err := w.check(st, repair(1, h1, "", change), nil); err != nil {
		t.Fatalf("a round that rules what triage left: %v", err)
	}
	mustRefuse(t, w.check(st, repair(1, h1, ""), nil), "ask tk-change is open and nothing holds it")
	mustRefuse(t, w.check(st, repair(1, h1, "", change, answer("tk-q", "again")), nil),
		"triage answered ask tk-q in this round")
}

// Only an answer of an ask's post is wordless, and a post that settles a
// question is told so in words.
func TestAWordlessAnswer(t *testing.T) {
	setup := func() (*world, string) {
		w := newWorld(t)
		w.postAsk("tk-thanks", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
		w.ask("tk-change", "")
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictApprove, "F1"))
		return w, w.step(1, "rule-and-repair")
	}
	f1 := finding("correctness", "F1", review.RulingDeclined)
	change := review.Ruling{Ask: "tk-change", Ruling: review.RulingDeclined, Reason: "a nit"}
	w, st := setup()
	if err := w.check(st, repair(1, h1, "", f1, change, wordless("tk-thanks", "A thank-you.")), nil); err != nil {
		t.Fatalf("a wordless answer of a post: %v", err)
	}
	declined := wordless("tk-thanks", "r")
	declined.Ruling = review.RulingDeclined
	wordlessFinding := f1
	wordlessFinding.Wordless = true
	settling := wordless("tk-thanks", "r")
	settling.Settles = "tk-g"
	for _, c := range []struct {
		name string
		rs   []review.Ruling
		why  string
	}{
		{"a decline", []review.Ruling{f1, change, declined}, "only an answer of an ask's post is wordless"},
		{"a finding", []review.Ruling{wordlessFinding, change, answer("tk-thanks", "r")}, "only an answer of an ask's post is wordless"},
		{"an ask with no post", []review.Ruling{f1, wordless("tk-change", "r"), answer("tk-thanks", "r")}, "carries no person's post"},
		{"one that settles a question", []review.Ruling{f1, change, settling}, "a post that settles a question is told so"},
	} {
		t.Run(c.name, func(t *testing.T) {
			w, st := setup()
			mustRefuse(t, w.check(st, repair(1, h1, "", c.rs...), nil), c.why)
		})
	}
}

// A round in which triage picked no check and answered every ask the round
// can take leaves rule-and-repair nothing: the account says so, the round
// passes with no output of rule-and-repair's, and its record closes the asks
// triage answered.
func TestARoundTriageAnswersWhole(t *testing.T) {
	w := newWorld(t)
	w.store.WorkRecordGate = true
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.postAsk("tk-lgtm", "Approval message", "pullrequestreview-200", "2026-11-12T03:00:00Z")
	w.output(answers(1, []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head."),
		wordless("tk-lgtm", "An approval that asks for nothing.")}))
	v := w.passed(1)
	mustPass(t, v)
	if left := v.Run.Left(1, v.Asks); len(left) != 0 {
		t.Fatalf("triage left rule-and-repair %q; want nothing", left)
	}
	account := v.Explain()
	for _, want := range []string{
		"answered 2 ask(s)",
		"ask tk-q: answered: The suite took 7 minutes at this head.",
		"ask tk-lgtm: answered with the city's 👍 alone: An approval that asks for nothing.",
		"rule-and-repair: nothing written, and triage left it nothing",
	} {
		if !strings.Contains(account, want) {
			t.Fatalf("the account lacks %q:\n%s", want, account)
		}
	}
	if strings.Contains(account, "\nask tk-q (") {
		t.Fatalf("the account lists an ask triage answered among those left:\n%s", account)
	}
	got := w.record(1)
	want := []review.ClosedAsk{{ID: "tk-lgtm", Ruling: review.RulingAnswered, Outcome: "no-op"},
		{ID: "tk-q", Ruling: review.RulingAnswered, Outcome: "no-op"}}
	if !reflect.DeepEqual(sortedClosed(got.Closed), want) {
		t.Fatalf("Record closed %+v; want %+v", got.Closed, want)
	}
	if !reflect.DeepEqual(w.results(), []review.Result{{Head: h1, Target: target, Passed: true, Run: root}}) {
		t.Fatalf("review_results = %+v; want a pass at %s", w.results(), h1)
	}
}

// sortedClosed is the asks Record closed in id order.
func sortedClosed(cs []review.ClosedAsk) []review.ClosedAsk {
	out := slices.Clone(cs)
	slices.SortFunc(out, func(a, b review.ClosedAsk) int { return strings.Compare(a.ID, b.ID) })
	return out
}

// A round in which triage picked a check or left an ask waits on
// rule-and-repair's rulings, whose account names what triage left, and passes
// once they rule it, with triage's answers closing beside them.
func TestARoundTriageLeavesWorkIn(t *testing.T) {
	w := newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.output(answers(1, []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head.")}, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove))
	v := w.passed(1)
	mustFail(t, v, "rule-and-repair wrote no rulings in iteration 1, and triage left it the correctness lane")
	if !strings.Contains(v.Explain(), "rule-and-repair: nothing written, and triage left it the correctness lane") {
		t.Fatalf("the account does not name what triage left:\n%s", v.Explain())
	}

	w = newWorld(t)
	w.store.WorkRecordGate = true
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.postAsk("tk-change", "Inline comment", "discussion_r260", "2026-11-12T03:00:00Z")
	w.output(answers(1, []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head.")}))
	mustFail(t, w.passed(1), "triage left it ask tk-change")
	w.output(repair(1, h1, "", review.Ruling{Ask: "tk-change", Ruling: review.RulingDeclined, Reason: "a nit"}))
	mustPass(t, w.passed(1))
	got := w.record(1)
	want := []review.ClosedAsk{{ID: "tk-change", Ruling: review.RulingDeclined, Outcome: "no-op"},
		{ID: "tk-q", Ruling: review.RulingAnswered, Outcome: "no-op"}}
	if !reflect.DeepEqual(sortedClosed(got.Closed), want) {
		t.Fatalf("Record closed %+v; want %+v", got.Closed, want)
	}
}

// The head's comment carries triage's answers beside rule-and-repair's
// rulings, and renders a round whose only rulings are triage's.
func TestTheHeadsCommentCarriesTriagesAnswers(t *testing.T) {
	w := newWorld(t)
	w.postAsk("tk-q", "Conversation comment", "issuecomment-5", "2026-11-12T03:00:00Z")
	w.output(answers(1, []review.Ruling{answer("tk-q", "The suite took 7 minutes at this head.")}))
	run, err := review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	asks, err := review.AsksOn(w.ledger(), prBead)
	if err != nil {
		t.Fatal(err)
	}
	got := review.Comment(run, 1, asks)
	for _, want := range []string{
		review.Mark(root, h1),
		"no check ran at this head. The round answered 1.",
		"(tk-q): Answered: The suite took 7 minutes at this head.",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("the comment lacks %q:\n%s", want, got)
		}
	}

	w.postAsk("tk-change", "Inline comment", "discussion_r260", "2026-11-12T03:00:00Z")
	w.output(repair(1, h1, "", review.Ruling{Ask: "tk-change", Ruling: review.RulingDeclined, Reason: "a nit"}))
	if run, err = review.ReadRun(w.ledger(), root); err != nil {
		t.Fatal(err)
	}
	if asks, err = review.AsksOn(w.ledger(), prBead); err != nil {
		t.Fatal(err)
	}
	got = review.Comment(run, 1, asks)
	for _, want := range []string{
		"The round declined 1, answered 1.",
		"(tk-q): Answered: The suite took 7 minutes at this head.",
		"(tk-change): Declined, and the head carries no change for it: a nit",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("the comment lacks %q:\n%s", want, got)
		}
	}
}
