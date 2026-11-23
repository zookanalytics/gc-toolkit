package review

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A step of a review run writes its output once, before it closes, and Gas
// City keeps it as the step's gc.output_json. The write is native. What the
// review domain adds is the check before it: an output the pass rule would
// read as not written, or one that names another iteration, another head or a
// finding no lane raised, would spend an attempt on a step's slip, and a
// triage output whose checks are not an array stops the run, because its
// fan-out cannot read it. So the step's text runs gctk review output, which
// reads what the step wrote and prints it as the store keeps it, or refuses it
// with the reason, and the step writes what it printed.
//
// A correctness lane's approve carries the guidance-edit guard. A change that
// edits its own review guidance, review-checks.toml or a docs/review-*.md, was
// reviewed under that edit, since every reader takes the guidance at the commit
// it judges, so its approve names the edit to the person who approves the
// merge: it is refused until needs_you says what the edit changes about the
// review. Paths that cannot be listed leave the edit unchecked, and needs_you
// then says so, so the approver reads the diff for one.

// OutputRequest is one step's output to check: the step's bead, the text the
// step wrote, the checkouts that can read the reviewed commit, the reader of
// the withdrawal filed on a bead for a head, open or closed, "" when none is,
// which the pr domain answers (pr.WithdrawalFor), and the reader of the
// person's post on the PR at pr that an ask's reason names, "" when it names
// none, which the pr domain answers too (pr.PostNamed).
type OutputRequest struct {
	Step       string
	Raw        []byte
	Repos      []string
	Withdrawal func(bead, head string) (string, error)
	Post       func(reason, pr string) string
}

// Refused is the error of an output the step must write again: why.
type Refused struct{ Why string }

func (e *Refused) Error() string { return e.Why }

func refuse(format string, args ...any) error { return &Refused{Why: fmt.Sprintf(format, args...)} }

// Output checks the output a step wrote and returns it as the store keeps it:
// compact JSON in the shape the step writes, naming the iteration it runs in.
// A read that fails returns the store's error.
func Output(l *ledger.Ledger, req OutputRequest) ([]byte, error) {
	st, err := ReadStep(l, req.Step)
	if err != nil {
		return nil, err
	}
	if st.Output == "" {
		return nil, refuse("%s (%s) is not a step that writes an output: triage, a lane and rule-and-repair do", st.ID, st.Ref)
	}
	var head struct {
		Review    *string `json:"review"`
		Iteration int     `json:"iteration"`
	}
	if err := json.Unmarshal(req.Raw, &head); err != nil {
		return nil, refuse("the output is not one JSON object: %v", err)
	}
	if head.Review == nil || *head.Review != st.Output {
		got := "none"
		if head.Review != nil {
			got = fmt.Sprintf("%q", *head.Review)
		}
		return nil, refuse("%s writes a %s output, so its review field reads %q, not %s", st.ID, st.Output, st.Output, got)
	}
	if head.Iteration != 0 && head.Iteration != st.Iteration {
		return nil, refuse("%s runs in iteration %d, and the output names iteration %d", st.ID, st.Iteration, head.Iteration)
	}
	run, n := st.Run, st.Iteration
	var v any
	switch st.Output {
	case OutputTriage:
		v, err = triageOutput(l, st, req)
	case OutputLane:
		v, err = laneOutput(run, n, req)
	case OutputRepair:
		v, err = repairOutput(l, st, req)
	}
	if err != nil {
		return nil, err
	}
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimRight(b.Bytes(), "\n"), nil
}

// decode reads raw into v in the shape, refusing a field the shape does not
// name, as the run's reader does.
func decode(raw []byte, v any, what string) error {
	if err := strict(string(raw), v); err != nil {
		return refuse("the %s output does not read in its shape (services/gctk/review/run.go): %v", what, err)
	}
	return nil
}

// triageOutput checks triage's output. A head ruled material keeps the
// approvals given before it only until the landing order carries out the
// withdrawal triage files for it, so the output stands only once that
// withdrawal is on the bead that owns the PR, open or closed. Its answers
// stand by triageAnswers.
func triageOutput(l *ledger.Ledger, st *Step, req OutputRequest) (*Triage, error) {
	run, n := st.Run, st.Iteration
	var t Triage
	if err := decode(req.Raw, &t, OutputTriage); err != nil {
		return nil, err
	}
	t.Iteration = n
	if want := run.HeadOf(n); t.Head != want {
		return nil, refuse("iteration %d judges %s, and the output names the head %q", n, want, t.Head)
	}
	seen := map[string]bool{}
	for _, p := range t.Checks {
		switch {
		case !ValidName(p.Check):
			return nil, refuse("a pick names the check %q, which is not a check's name", p.Check)
		case seen[strings.ToLower(p.Check)]:
			return nil, refuse("the check %s is picked twice", p.Check)
		case p.Head != t.Head:
			return nil, refuse("the %s pick names the head %q, not the head triage judged, %s", p.Check, p.Head, t.Head)
		}
		seen[strings.ToLower(p.Check)] = true
	}
	if t.Checks == nil {
		t.Checks = []Pick{}
	}
	if t.Material {
		if req.Withdrawal == nil {
			return nil, errors.New("no reader of withdrawals was given, so a material ruling cannot be checked")
		}
		id, err := req.Withdrawal(run.PRBead, t.Head)
		if err != nil {
			return nil, err
		}
		if id == "" {
			return nil, refuse("triage rules %s material, and no withdrawal for it is filed on %s: withdraw the approvals "+
				"given before it (review-run.sh withdraw), then write the output", t.Head, run.PRBead)
		}
	}
	if err := triageAnswers(l, st, t.Rulings, req); err != nil {
		return nil, err
	}
	return &t, nil
}

// triageAnswers is why triage's rulings do not stand, nil when they do. Triage
// answers a person's post that asks for no change to the branch and no
// person's decision, and leaves every other ask to rule-and-repair, so each of
// its rulings names, once, an ask the round can take whose reason names a
// person's post on the PR, and rules it answered, with the reason the PR
// shows and no commit, gate or question it settles. It answers nothing while a
// question a review run put to a person is open on the bead that owns the PR,
// since a post may settle that question, and no ask filed before such a
// question was put, which may be the question's own: rule-and-repair rules
// those by the person's answer. A read that fails returns the store's error.
func triageAnswers(l *ledger.Ledger, st *Step, rs []Ruling, req OutputRequest) error {
	if len(rs) == 0 {
		return nil
	}
	if req.Post == nil {
		return errors.New("no reader of the posts an ask names was given, so triage's answers cannot be checked")
	}
	asks, err := AsksOn(l, st.Run.PRBead)
	if err != nil {
		return err
	}
	questions, err := questionsOn(l, st.Run.PRBead)
	if err != nil {
		return err
	}
	for _, q := range questions {
		if q.open {
			return refuse("the question at %s is open on %s, and a post may settle it, which rule-and-repair rules: "+
				"answer no post while it is open", q.id, st.Run.PRBead)
		}
	}
	seen := map[string]bool{}
	for _, r := range rs {
		switch {
		case r.Ask == "":
			return refuse("a ruling names no ask, and triage rules no lane's finding, since the lanes run after it")
		case r.Check != "" || r.Finding != "":
			return refuse("a ruling names the ask %s and a lane's finding at once", r.Ask)
		case seen[r.Ask]:
			return refuse("%s is ruled twice", r.Subject())
		}
		seen[r.Ask] = true
		i := slices.IndexFunc(asks, func(a Ask) bool { return a.ID == r.Ask })
		switch {
		case i < 0 || !asks[i].Takeable():
			return refuse("%s is not an ask the round can take: open on the bead, with nothing holding it", r.Subject())
		case req.Post(asks[i].Reason, st.PR()) == "":
			return refuse("%s carries no person's post on the PR, and triage answers only a post: leave it to rule-and-repair", r.Subject())
		case r.Ruling != RulingAnswered:
			return refuse("%s is ruled %q, and triage rules a post only %s, leaving every other ruling to rule-and-repair",
				r.Subject(), r.Ruling, RulingAnswered)
		case strings.TrimSpace(r.Reason) == "":
			return refuse("%s is answered with no reason, and the reason is the answer the PR shows", r.Subject())
		case r.Commit != "" || r.Gate != "" || r.Settles != "" || r.Moot:
			return refuse("%s is answered with a commit, a gate or a question it settles, which only rule-and-repair names", r.Subject())
		}
		for _, q := range questions {
			if !after(asks[i].Filed, q.filed) {
				return refuse("%s was filed before the question at %s was put to a person, so it may be that question's own "+
					"ask, which rule-and-repair rules by the answer: leave it to rule-and-repair", r.Subject(), q.id)
			}
		}
	}
	return nil
}

// question is a gate through which a review run put a question to a person on
// the bead that owns a PR: its id, when it was filed, and whether it is open.
type question struct {
	id, filed string
	open      bool
}

// questionsOn is each question a review run put to a person on bead, open or
// closed: a human gate under a key QuestionKey opens, which bead waits on by a
// blocks edge. A read that fails returns the store's error.
func questionsOn(l *ledger.Ledger, bead string) ([]question, error) {
	owner, err := one(l, bead)
	if err != nil {
		return nil, err
	}
	edges, err := owner.Edges()
	if err != nil {
		return nil, &ledger.ReadError{ID: owner.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	var ids []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks && !slices.Contains(ids, e.ID) {
			ids = append(ids, e.ID)
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	rows, err := l.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	var out []question
	for _, g := range rows {
		if strings.EqualFold(g.IssueType(), "gate") && g.AwaitType() == "human" && strings.HasPrefix(g.AwaitID(), QuestionKey) {
			out = append(out, question{id: g.ID, filed: g.CreatedAt(), open: g.Status() != "closed"})
		}
	}
	return out, nil
}

// after reports whether the instant a is later than the instant b, each as the
// store writes a bead's times. An instant that does not read is later than
// none, and none is later than it.
func after(a, b string) bool {
	x, err := time.Parse(time.RFC3339Nano, a)
	if err != nil {
		return false
	}
	y, err := time.Parse(time.RFC3339Nano, b)
	return err == nil && x.After(y)
}

func laneOutput(run *Run, n int, req OutputRequest) (*Lane, error) {
	var ln Lane
	if err := decode(req.Raw, &ln, OutputLane); err != nil {
		return nil, err
	}
	ln.Iteration = n
	it := run.Iterations[n]
	if it == nil || it.Triage == nil {
		return nil, refuse("triage has written nothing in iteration %d, so no lane runs there", n)
	}
	if !slices.ContainsFunc(it.Triage.Checks, func(p Pick) bool { return strings.EqualFold(p.Check, ln.Check) }) {
		return nil, refuse("triage did not pick %q in iteration %d", ln.Check, n)
	}
	if ln.Head != it.Triage.Head {
		return nil, refuse("the %s lane of iteration %d reviews %s, and the output names the head %q", ln.Check, n, it.Triage.Head, ln.Head)
	}
	if ln.Verdict != VerdictApprove && ln.Verdict != VerdictRequestChanges {
		return nil, refuse("the verdict reads %q, not %s or %s", ln.Verdict, VerdictApprove, VerdictRequestChanges)
	}
	ids := map[string]bool{}
	blocking := 0
	for i := range ln.Findings {
		f := &ln.Findings[i]
		switch {
		case strings.TrimSpace(f.ID) == "":
			return nil, refuse("a finding names no id, so no ruling can answer it")
		case ids[f.ID]:
			return nil, refuse("the finding id %s is used twice", f.ID)
		case strings.TrimSpace(f.Locus) == "" || strings.TrimSpace(f.Message) == "":
			return nil, refuse("finding %s needs its locus and its message", f.ID)
		}
		ids[f.ID] = true
		if why := contract(f, ln.Check); why != "" {
			return nil, refuse("finding %s: %s", f.ID, why)
		}
		if f.Severity != "P2" {
			blocking++
		}
	}
	switch {
	case ln.Verdict == VerdictApprove && blocking > 0:
		return nil, refuse("an approve carries no blocking finding, and this set carries %d: a P0, a P1 or a finding with no grade", blocking)
	case ln.Verdict == VerdictRequestChanges && blocking == 0:
		return nil, refuse("request-changes needs a blocking finding, and this set carries none; when only P2s remain, the lane approves")
	}
	if ln.Findings == nil {
		ln.Findings = []Finding{}
	}
	if why := visual(&ln); why != "" {
		return nil, refuse("%s", why)
	}
	if strings.EqualFold(ln.Check, "correctness") && ln.Verdict == VerdictApprove && strings.TrimSpace(ln.NeedsYou) == "" {
		edits, err := GuidanceEdits(IndexSources{Repos: req.Repos}, run.Target, ln.Head)
		switch {
		case err != nil:
			ln.NeedsYou = fmt.Sprintf("The paths this change touches could not be listed (%v), so whether it edits its own review "+
				"guidance (review-checks.toml, docs/review-*.md) is unchecked; read its diff for such an edit before you approve the merge.", err)
		case len(edits) > 0:
			return nil, refuse("this change edits its own review guidance (%s), and its review ran under that edit, since every "+
				"reader takes the guidance at the commit it judges. A correctness approve names the edit to the person who approves "+
				"the merge: write needs_you saying what the edit changes about the review", strings.Join(edits, ", "))
		}
	}
	return &ln, nil
}

// repairOutput checks rule-and-repair's output: a ruling for every finding a
// lane raised and every ask the round can take that triage did not answer,
// each standing by checkRuling, and none for an ask triage answered, whose
// answer the round already posted.
func repairOutput(l *ledger.Ledger, st *Step, req OutputRequest) (*Repair, error) {
	run, n := st.Run, st.Iteration
	var rp Repair
	if err := decode(req.Raw, &rp, OutputRepair); err != nil {
		return nil, err
	}
	rp.Iteration = n
	it := run.Iterations[n]
	if it == nil || it.Triage == nil {
		return nil, refuse("triage has written nothing in iteration %d, so there is nothing to rule", n)
	}
	if rp.Head != it.Triage.Head {
		return nil, refuse("iteration %d judged %s, and the output names the head %q", n, it.Triage.Head, rp.Head)
	}
	asks, err := AsksOn(l, run.PRBead)
	if err != nil {
		return nil, err
	}
	answered := map[string]bool{}
	for _, r := range it.Triage.Rulings {
		answered[r.Ask] = true
	}
	declined := earlierDeclines(run, n)
	subjects := map[subject]bool{}
	for _, r := range rp.Rulings {
		if r.Ask != "" && answered[r.Ask] {
			return nil, refuse("triage answered %s in this round, so rule-and-repair does not rule it again", r.Subject())
		}
		if err := checkRuling(r, it, asks, declined); err != nil {
			return nil, err
		}
		if subjects[r.subject()] {
			return nil, refuse("%s is ruled twice", r.Subject())
		}
		subjects[r.subject()] = true
		if r.Wordless {
			if req.Post == nil {
				return nil, errors.New("no reader of the posts an ask names was given, so a wordless answer cannot be checked")
			}
			i := slices.IndexFunc(asks, func(a Ask) bool { return a.ID == r.Ask })
			if req.Post(asks[i].Reason, st.PR()) == "" {
				return nil, refuse("%s is answered wordless, and it carries no person's post on the PR for the city's 👍", r.Subject())
			}
		}
	}
	for _, ln := range it.Lanes {
		for _, f := range ln.Findings {
			if !subjects[Ruling{Check: ln.Check, Finding: f.ID}.subject()] {
				return nil, refuse("%s finding %s is not ruled", ln.Check, f.ID)
			}
		}
	}
	for _, a := range asks {
		if a.Takeable() && !answered[a.ID] && !subjects[Ruling{Ask: a.ID}.subject()] {
			return nil, refuse("ask %s is open and nothing holds it, so the round rules it", a.ID)
		}
	}
	if err := checkSettles(l, run.PRBead, rp.Rulings); err != nil {
		return nil, err
	}
	if rp.Pushed != "" && !git.IsObjectID(rp.Pushed) {
		return nil, refuse("the push %q is not a full object name", rp.Pushed)
	}
	if rp.Rulings == nil {
		rp.Rulings = []Ruling{}
	}
	return &rp, nil
}

// contract is why a lane's finding breaks the finding contract, "" when it
// keeps it, with its grade written upper-case: a grade is P0, P1 or P2, and
// every correctness finding carries one; a graded finding names its category
// and its failure scenario; a P0 or a P1 carries a verification that opens
// CONFIRMED or PLAUSIBLE and then the evidence; and a candidate whose
// verification is REFUTED is no finding at any grade. A P2 does not block, and
// a finding with no grade does.
func contract(f *Finding, check string) string {
	f.Severity = strings.ToUpper(strings.TrimSpace(f.Severity))
	verification := strings.TrimSpace(f.Verification)
	switch g := f.Severity; {
	case g != "" && g != "P0" && g != "P1" && g != "P2":
		return fmt.Sprintf("its severity reads %q, not P0, P1 or P2", g)
	case g == "" && strings.EqualFold(check, "correctness"):
		return "it has no severity, and every correctness finding is graded"
	case g != "" && (strings.TrimSpace(f.Category) == "" || strings.TrimSpace(f.FailureScenario) == ""):
		return "a graded finding names its category and its failure_scenario"
	case refutedVerification.MatchString(verification):
		return "its verification is REFUTED, and a refuted candidate is not a finding: leave it out, and keep its refutation in the trail"
	case (g == "P0" || g == "P1") && !confirmedVerification.MatchString(verification):
		return fmt.Sprintf("a %s carries a verification that opens CONFIRMED or PLAUSIBLE and then the evidence", g)
	}
	return ""
}

// visual is why a lane's visual decision does not stand, "" when it does,
// with each modality written lower-case. The demo check records its decision
// on every verdict: none when the change needs no visual, which leaves the
// check nothing to block on and so goes with an approve only, else the
// modality delivered. A fallback names the modality that fits and could not be
// produced here, screenshot or video, which costs more than the one delivered:
// repo-artifact, then screenshot, then video. No other check records one.
func visual(ln *Lane) string {
	ln.Visual = strings.ToLower(strings.TrimSpace(ln.Visual))
	ln.VisualFallbackFrom = strings.ToLower(strings.TrimSpace(ln.VisualFallbackFrom))
	if !strings.EqualFold(ln.Check, "demo") {
		if ln.Visual != "" || ln.VisualFallbackFrom != "" {
			return fmt.Sprintf("only the demo check records a visual decision, and this lane is %s", ln.Check)
		}
		return ""
	}
	cost := map[string]int{"repo-artifact": 1, "screenshot": 2, "video": 3}
	switch {
	case ln.Visual == "":
		return "the demo check records its visual decision on every verdict: none, repo-artifact, screenshot or video"
	case ln.Visual != "none" && cost[ln.Visual] == 0:
		return fmt.Sprintf("the visual reads %q, not none, repo-artifact, screenshot or video", ln.Visual)
	case ln.Visual == "none" && ln.Verdict != VerdictApprove:
		return "a visual of none says the change needs no visual, which leaves the demo check nothing to block on, so it goes with an approve only"
	case ln.VisualFallbackFrom == "":
		return ""
	case ln.VisualFallbackFrom != "screenshot" && ln.VisualFallbackFrom != "video":
		return fmt.Sprintf("the visual fallback reads %q, not screenshot or video, the modality that fits", ln.VisualFallbackFrom)
	case ln.Visual == "none":
		return "a fallback names the modality a delivered visual stands in for, and a visual of none delivers none"
	case cost[ln.Visual] >= cost[ln.VisualFallbackFrom]:
		return fmt.Sprintf("a fallback is cheaper than the modality it stands in for, so %s cannot be a fallback from %s", ln.Visual, ln.VisualFallbackFrom)
	}
	return ""
}

var (
	refutedVerification   = regexp.MustCompile(`(?i)^REFUTED([^[:alnum:]]|$)`)
	confirmedVerification = regexp.MustCompile(`(?i)^(CONFIRMED|PLAUSIBLE)[^[:alnum:]]+[^[:space:]]`)
)

// checkRuling is why one ruling of iteration it's round does not stand: a
// subject no lane raised and no ask the round can take, a ruling outside the
// set, a must-fix with no fixing commit, a commit on a ruling that changes no
// code, a question with no gate, a wordless ruling that is not an ask's answer
// or that settles a question, and a fix for an ask an earlier round of the run
// declined, which a later ruling of its own overrules only through an ask that
// carries it.
func checkRuling(r Ruling, it *Iteration, asks []Ask, declined map[string]string) error {
	switch {
	case r.Ask != "" && (r.Check != "" || r.Finding != ""):
		return refuse("a ruling names the ask %s and a lane's finding at once", r.Ask)
	case r.Ask != "":
		if !slices.ContainsFunc(asks, func(a Ask) bool { return a.ID == r.Ask && a.Takeable() }) {
			return refuse("%s is not an ask the round can take: open on the bead, with nothing holding it", r.Subject())
		}
	case r.Check == "" || r.Finding == "":
		return refuse("a ruling names neither an ask nor a lane's check and finding")
	default:
		ln, ok := lane(it, r.Check)
		if !ok || !slices.ContainsFunc(ln.Findings, func(f Finding) bool { return r.rulesFinding(ln.Check, f.ID) }) {
			return refuse("no lane of this iteration raised %s", r.Subject())
		}
	}
	if !slices.Contains(rulings, r.Ruling) {
		return refuse("%s is ruled %q, which is not a ruling (%s)", r.Subject(), r.Ruling, strings.Join(rulings, ", "))
	}
	switch {
	case r.Ruling == RulingMustFix && !git.IsObjectID(r.Commit):
		return refuse("%s is ruled must-fix and names no commit that fixes it (a full object name)", r.Subject())
	case r.Ruling != RulingMustFix && r.Commit != "":
		return refuse("%s is ruled %s, which changes no code, and names the commit %s", r.Subject(), r.Ruling, r.Commit)
	case r.Ruling == RulingQuestion && strings.TrimSpace(r.Gate) == "":
		return refuse("%s is put to a person and names no gate", r.Subject())
	case r.Ruling != RulingQuestion && r.Gate != "":
		return refuse("%s is ruled %s and names the gate %s, which only a question goes to", r.Subject(), r.Ruling, r.Gate)
	case strings.TrimSpace(r.Reason) == "":
		return refuse("%s is ruled %s with no reason", r.Subject(), r.Ruling)
	case r.Wordless && (r.Ask == "" || r.Ruling != RulingAnswered):
		return refuse("%s is ruled %s and wordless, and only an answer of an ask's post is wordless", r.Subject(), r.Ruling)
	case r.Wordless && r.Settles != "":
		return refuse("%s settles the question at %s and is wordless, and a post that settles a question is told so", r.Subject(), r.Settles)
	}
	if was, ok := declined[r.Ask]; ok && r.Ask != "" && r.Ruling == RulingMustFix {
		return refuse("an earlier round of this run ruled %s %s, so no repair changes code for it; a ruling that overrules that "+
			"comes as an ask of its own, which the round rules must-fix", r.Subject(), was)
	}
	return nil
}

// checkSettles is why the round's rulings do not stand on the questions they
// settle: moot with no gate, a gate settled by a finding's ruling or by a
// question's, a gate two rulings settle, one the round also puts a question
// to, and one that is not an open human gate on the bead that owns the PR
// under a question's key. A read that fails returns the store's error.
func checkSettles(l *ledger.Ledger, bead string, rs []Ruling) error {
	asked := map[string]bool{}
	for _, r := range rs {
		if r.Ruling == RulingQuestion {
			asked[strings.TrimSpace(r.Gate)] = true
		}
	}
	settled := map[string]string{}
	var owner *ledger.Record
	for _, r := range rs {
		gate := strings.TrimSpace(r.Settles)
		switch {
		case gate == "" && r.Moot:
			return refuse("%s is ruled moot and names no gate whose question it makes moot", r.Subject())
		case gate == "":
			continue
		case r.Ask == "":
			return refuse("%s names the gate %s it settles, and only the ruling of an ask for a person's post settles one",
				r.Subject(), gate)
		case r.Ruling == RulingQuestion:
			return refuse("%s is put to a person and names the gate %s it settles, and a question settles none", r.Subject(), gate)
		case settled[gate] != "":
			return refuse("%s and %s both settle the gate %s, which one post answers", settled[gate], r.Subject(), gate)
		case asked[gate]:
			return refuse("%s settles the gate %s, which the round puts a question to", r.Subject(), gate)
		}
		settled[gate] = r.Subject()
		if owner == nil {
			o, err := one(l, bead)
			if err != nil {
				return err
			}
			owner = o
		}
		why, err := openQuestion(l, owner, gate)
		if err != nil {
			return err
		}
		if why != "" {
			return refuse("%s settles %s, which %s", r.Subject(), gate, why)
		}
	}
	return nil
}

// openQuestion says why gate is not a question a review run put to a person
// that holds owner, the bead that owns the PR, and is empty when it is: an
// open human gate under a key QuestionKey opens, with owner's blocks edge onto
// it. A read that fails returns the store's error.
func openQuestion(l *ledger.Ledger, owner *ledger.Record, gate string) (string, error) {
	rows, err := l.Find(ledger.ByID(gate).WithClosed())
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "the store does not hold", nil
	}
	g := rows[0]
	switch {
	case !strings.EqualFold(g.IssueType(), "gate") || g.AwaitType() != "human":
		return "is no human gate", nil
	case !strings.HasPrefix(g.AwaitID(), QuestionKey):
		return fmt.Sprintf("is keyed %q, which is no question's key (%s<slug>)", g.AwaitID(), QuestionKey), nil
	case g.Status() == "closed":
		return "is closed already", nil
	}
	edges, err := owner.Edges()
	if err != nil {
		return "", &ledger.ReadError{ID: owner.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	if !slices.ContainsFunc(edges, func(e ledger.Edge) bool { return e.Type == ledger.EdgeBlocks && e.ID == gate }) {
		return "does not hold " + owner.ID, nil
	}
	return "", nil
}

// earlierDeclines is each ask an earlier round of the run ruled declined or
// deferred, with that ruling.
func earlierDeclines(run *Run, n int) map[string]string {
	out := map[string]string{}
	for _, m := range slices.Sorted(maps.Keys(run.Iterations)) {
		rp := run.Iterations[m].Repair
		if m >= n || rp == nil {
			continue
		}
		for _, r := range rp.Rulings {
			if r.Ask != "" && (r.Ruling == RulingDeclined || r.Ruling == RulingDeferred) {
				out[r.Ask] = r.Ruling
			}
		}
	}
	return out
}
